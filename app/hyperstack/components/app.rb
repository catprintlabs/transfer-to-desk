class App < HyperComponent
  def cases_per_hour
    (DeskCase.count / ((DeskCase.order_by_created_at.last.created_at - DeskCase.order_by_created_at.first.created_at) / 3600.to_f)) rescue 5000.0
  end

  def days_to_completion
    Integer(Stat.find_by_stat('cases_remaining').value).to_f / (cases_per_hour * 24) rescue 5.0
  end

  def completed_cases_per_hour
    (DeskCase.completed.count / ((DeskCase.completed_order_by_updated_at.last.updated_at - DeskCase.completed_order_by_updated_at.first.updated_at) / 3600.to_f)) rescue 150.0
  end

  def days_to_complete_transfer
    (Integer(Stats.starting_entries) - DeskCase.completed.count).to_f / (completed_cases_per_hour * 24) rescue 10.0
  end

  render do
    TABLE do
      TR do
        TH { 'stat' }
        TH { 'value' }
      end
      TR do
        TD { 'cases copied to DB' }
        TD { DeskCase.count.to_s }
      end
      TR do
        TD { 'cases copied to freshdesk' }
        TD { DeskCase.completed.count.to_s }
      end
      if DeskCase.count > 1
        TR do
          TD { 'time stamp of last case copied to DB' }
          TD { DeskCase.last&.case_created_at&.to_s }
        end
        TR do
          TD { 'cases per hour' }
          TD { cases_per_hour.to_i.to_s }
        end
        TR do
          TD { 'estimated days to transfer to db' }
          TD { days_to_completion.to_s }
        end
        if DeskCase.completed.count > 1
          TR do
            TD { 'time stamp of last case transfered to Freshdesk' }
            TD { DeskCase.completed.last&.case_created_at&.to_s }
          end
          TR do
            TD { 'cases per hour' }
            TD { completed_cases_per_hour.to_i.to_s }
          end
          TR do
            TD { 'estimated days to complete transfer' }
            TD { days_to_complete_transfer.to_s }
          end
        end
      end
      Stat.each do |stat|
        TR do
          TD { stat.stat }
          TD { stat.value }
        end
      end
      TR do
        TD { 'number of failures' }
        TD { DeskCase.failed.count.to_s }
      end
      if DeskCase.failed.count.positive?
        TR do
          TD(colspan: 2) { 'last 10 failures'}
        end
        DeskCase.failed.last(10).each do |failure|
          TR do
            TD { failure.desk_id.to_s }
            TD { failure.failed }
          end
        end
      end
    end
  end
end
