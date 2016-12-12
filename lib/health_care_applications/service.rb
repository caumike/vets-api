# frozen_string_literal: true
require 'soap/middleware/request/headers'
require 'soap/middleware/response/parse'
require 'health_care_applications/settings'

module HealthCareApplications
  class Service
    def health_check
      submission = soap.build_request(:get_form_submission_status, message:
        { formSubmissionId: HealthCareApplications::Settings::HEALTH_CHECK_ID })
      response = post(submission)
      root = response.body.locate('S:Envelope/S:Body/retrieveFormSubmissionStatusResponse').first
      {
        id: root.locate('formSubmissionId').first.text.to_i,
        timestamp: root.locate('timeStamp').first.text
      }
    end

    def self.options
      opts = {
        url: HealthCareApplications::Settings::ENDPOINT,
        ssl: {
          verify: true,
          cert_store: HealthCareApplications::Settings::CERT_STORE
        }
      }
      if HealthCareApplications::Settings::SSL_CERT && HealthCareApplications::Settings::SSL_KEY
        opts[:ssl].merge!(client_cert: HealthCareApplications::Settings::SSL_CERT,
                          client_key: HealthCareApplications::Settings::SSL_KEY)
      end
      opts
    end

    private

    def post(submission)
      connection.post '', submission.body
    end

    def soap
      # Savon *seems* like it should be setting these things correctly
      # from what the docs say. Our WSDL file is weird, maybe?
      Savon.client(wsdl: HealthCareApplications::Settings::WSDL,
                   env_namespace: :soap,
                   element_form_default: :qualified,
                   namespaces: {
                     'xmlns:tns': 'http://va.gov/service/esr/voa/v1'
                   },
                   namespace: 'http://va.gov/schema/esr/voa/v1')
    end

    def connection
      @conn ||= Faraday.new(HealthCareApplications::Service.options) do |conn|
        conn.options.open_timeout = 10  # TODO(molson): Make a config/setting
        conn.options.timeout = 15       # TODO(molson): Make a config/setting
        conn.use SOAP::Middleware::Request::Headers
        conn.use SOAP::Middleware::Response::Parse, name: 'HCA-ES'
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
