class App < HyperComponent
  render do
    TABLE do
      TR do
        TH { 'stat' }
        TH { 'value' }
      end
      Stat.each do |stat|
        TR do
          TD { stat.stat }
          TD { stat.value }
        end
      end
    end
  end
end
