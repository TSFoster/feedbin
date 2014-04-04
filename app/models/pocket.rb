class Pocket
  include HTTParty
  base_uri 'https://getpocket.com/v3'
  headers 'Content-Type' => 'application/json; charset=UTF-8', 'X-Accept' => 'application/json'

  def redirect_url(token)
    if token.present?
      uri = URI.parse(self.class.base_uri)
      uri.path = '/auth/authorize'
      uri.query = { 'request_token' => token, 'redirect_uri' => redirect_uri }.to_query
      uri.to_s
    else
      false
    end
  end

  def request_token
    options = {
      body: {consumer_key: ENV['POCKET_CONSUMER_KEY'], redirect_uri: redirect_uri}.to_json
    }
    response = self.class.post('/oauth/request', options)
    if response.code == 200
      response.parsed_response['code']
    else
      report_error(response)
      false
    end
  end

  def oauth_authorize(code)
    options = {
      body: {consumer_key: ENV['POCKET_CONSUMER_KEY'], code: code}.to_json
    }
    response = self.class.post('/oauth/authorize', options)
    if response.code == 200
      response.parsed_response['access_token']
    else
      report_error(response)
      false
    end
  end

  def add(access_token, url)
    options = {
      body: { url: url, access_token: access_token, consumer_key: ENV['POCKET_CONSUMER_KEY'] }.to_json
    }
    self.class.post('/add', options)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_url('pocket', host: ENV['PUSH_URL'])
  end

  def report_error(parameters)
    Honeybadger.notify(
      error_class: "Pocket HTTP",
      error_message: "Pocket HTTP Failure",
      parameters: parameters
    )
  end


end