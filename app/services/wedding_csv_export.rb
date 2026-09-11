require "csv"
require "zip"

class WeddingCsvExport
  TABLES = {
    tasks: %w[id title description status assignee category starts_on due_on origin source_key],
    households: %w[id code name notes archived cash_gift_rule_id],
    guests: %w[id name side relationship gender age_group attendance invitation_status household_id seating_table_id meal_set_id roles allergies notes],
    seating_tables: %w[id label capacity position_x position_y],
    meal_sets: %w[id name target_age_group unit_price_yen default_for_target notes],
    gift_sets: %w[id name notes],
    gift_set_items: %w[id gift_set_id kind name unit_price_yen tax_basis tax_rate rounding],
    gift_assignments: %w[id household_id gift_set_id quantity included budget_item_id notes],
    guest_gift_assignments: %w[id guest_id gift_set_id quantity included budget_item_id notes],
    budget_items: %w[id direction category title amount_yen certainty inclusion calculation_mode quantity_basis unit_price manual_quantity tax_basis tax_rate rounding source_kind source_id],
    money_movements: %w[id budget_item_id kind amount_yen occurred_on note idempotency_key],
    planning_items: %w[id title category notes position],
    planning_options: %w[id planning_item_id title description status reference_price_yen],
    music_details: %w[id planning_option_id wish_track_a wish_track_b selected_track artist start_offset_seconds scene],
    documents: %w[id title source_type direction occurred_at created_at sample attachment_count]
  }.freeze

  def self.call(wedding)
    new(wedding).call
  end

  def initialize(wedding)
    @wedding = wedding
  end

  def call
    Zip::OutputStream.write_buffer do |zip|
      datasets.each do |name, rows|
        zip.put_next_entry("#{name}.csv")
        zip.write("\uFEFF" + CSV.generate(encoding: Encoding::UTF_8) do |csv|
          csv << TABLES.fetch(name)
          rows.each { |row| csv << row.map { |value| clean(value) } }
        end)
      end
    end.string
  end

  private

  def datasets
    planning_items = @wedding.planning_items.includes(planning_options: :music_detail).order(:position, :id).to_a
    gift_sets = @wedding.gift_sets.includes(:gift_set_items).order(:id).to_a
    {
      tasks: @wedding.tasks.order(:id).map { |r| values(r, %i[id title description status assignee category starts_on due_on origin source_key]) },
      households: @wedding.households.order(:id).map { |r| values(r, %i[id code name notes archived cash_gift_rule_id]) },
      guests: @wedding.guests.order(:id).map { |r| values(r, %i[id name side relationship gender age_group attendance invitation_status household_id seating_table_id meal_set_id roles allergies notes]) },
      seating_tables: @wedding.seating_tables.order(:id).map { |r| values(r, %i[id label capacity position_x position_y]) },
      meal_sets: @wedding.meal_sets.order(:id).map { |r| values(r, %i[id name target_age_group unit_price_yen default_for_target notes]) },
      gift_sets: gift_sets.map { |r| values(r, %i[id name notes]) },
      gift_set_items: gift_sets.flat_map { |set| set.gift_set_items.order(:id).map { |r| values(r, %i[id gift_set_id kind name unit_price_yen tax_basis tax_rate rounding]) } },
      gift_assignments: @wedding.gift_assignments.order(:id).map { |r| values(r, %i[id household_id gift_set_id quantity included budget_item_id notes]) },
      guest_gift_assignments: @wedding.guest_gift_assignments.order(:id).map { |r| values(r, %i[id guest_id gift_set_id quantity included budget_item_id notes]) },
      budget_items: @wedding.budget_items.order(:id).map { |r| values(r, %i[id direction category title amount_yen certainty inclusion calculation_mode quantity_basis unit_price manual_quantity tax_basis tax_rate rounding source_kind source_id]) },
      money_movements: @wedding.money_movements.order(:id).map { |r| values(r, %i[id budget_item_id kind amount_yen occurred_on note idempotency_key]) },
      planning_items: planning_items.map { |r| values(r, %i[id title category notes position]) },
      planning_options: planning_items.flat_map { |item| item.planning_options.order(:id).map { |r| values(r, %i[id planning_item_id title description status reference_price_yen]) } },
      music_details: planning_items.flat_map { |item| item.planning_options.filter_map(&:music_detail).sort_by(&:id).map { |r| values(r, %i[id planning_option_id wish_track_a wish_track_b selected_track artist start_offset_seconds scene]) } },
      documents: @wedding.documents.with_attached_attachments.order(:id).map { |r| values(r, %i[id title source_type direction occurred_at created_at sample]) + [r.attachments.size] }
    }
  end

  def values(record, fields)
    fields.map { |field| record.public_send(field) }
  end

  def clean(value)
    return "" if value.nil?
    text = value.is_a?(Array) || value.is_a?(Hash) ? value.to_json : value.to_s
    text.match?(/\A[\s]*[=+\-@]/) ? "'#{text}" : text
  end
end
