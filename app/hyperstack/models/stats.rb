class Stats
  class << self
    def method_missing(stat, value = nil)
      stat = stat.to_s
      if stat =~ /.+=$/
        stat = stat.gsub(/=$/, '')
        if (record = Stat.find_by_stat(stat))
          record.update(value: value)
        else
          Stat.create(stat: stat, value: value)
        end
      else
        v = Stat.find_by_stat(stat)&.value
        Float(v) rescue v
      end
    end
  end
end
