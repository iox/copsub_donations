class ExchangeRate
  require 'nokogiri'

  # This class connects to the National Bank and retrieves the exchange rate once a day
  EXCHANGE_URL = "http://www.nationalbanken.dk/_vti_bin/DN/DataService.svc/CurrencyRatesXML?lang=en"

  def self.get(currency)
    @last_update ||= Time.now
    if !@doc || @last_update < Time.now - 24.hours
      self.update_exchange_rates
    end

    if currency.in? ['USD', 'EUR', 'CAD', 'GBP']
      rate_string = @doc.search("[code='#{currency}']").first.attributes["rate"].value
      return rate_string.to_f / 100
    else
      return 1
    end
  end

  def self.update_exchange_rates
    response = Net::HTTP.get_response(URI.parse(EXCHANGE_URL))
    if response.code == "200"
      @last_update = Time.now
      @doc = Nokogiri::XML(response.body)
    else
      Rails.logger.error "Could not connect to exchange rate server"
    end
  end

end