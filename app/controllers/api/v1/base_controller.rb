# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApiController
      def process_message
        # identify provider based on the token
        provider = ProviderApplication.find_by(application_id: doorkeeper_token.application_id).provider

        bundle_json = request.body.read

        fhir_manager = FhirUtilities.new
        fhir = fhir_manager.fhir
        bundle = fhir::Json.from_json(bundle_json)

        profile_id = find_profile_id(bundle)
        profile = Profile.find(profile_id)

        # puts "REQUEST.BODY.READ"
        # puts bundle_json
        bundle_json_utf = bundle_json.force_encoding('UTF-8')

        dr = DataReceipt.new(profile: profile,
                             provider: provider,
                             data: bundle_json_utf,
                             data_type: 'fhir_bundle_edr')
        dr.save!

        # run the sync job asynchronously, so the request returns quickly
        # set fetch = false, so that it doesn't fetch, it only processes the things we added
        SyncProfileJob.perform_later(profile, false)

        response = build_response(bundle)
        render json: response.to_json, status: :ok
      end

      private

      def find_profile_id(bundle)
        params = bundle.entry.find { |e| e.resource.resourceType == 'Parameters' }.resource
        params.parameter.find { |p| p.name == 'health_data_manager_profile_id' }.value
      end

      def build_response(bundle)
        original_message = bundle.entry[0].resource

        message_header = { 'resourceType' => 'MessageHeader',
                           'timestamp' => Time.now.iso8601,
                           'event' => { 'system' => 'urn:health_data_manager', 'code' => 'EDR', 'display' => 'Encounter Data Receipt' },
                           'source' => { 'name' => 'Rosie', 'endpoint' => 'urn:health_data_manager' },
                           'response' => { 'identifier' => original_message.id, 'code' => 'ok' } }

        fhir_manager = FhirUtilities.new
        fhir = fhir_manager.fhir
        fhir::Bundle.new('type' => 'message',
                         'entry' => [{ 'resource' => message_header }])
      end
    end
  end
end
