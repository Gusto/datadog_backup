# frozen_string_literal: true

module DatadogBackup
  # Workflow specific overrides for backup and restore.
  class Workflows < Resources
    def all
      get_all
    end

    def backup
      LOGGER.info("Starting workflows backup on #{::DatadogBackup::ThreadPool::TPOOL.max_length} threads")

      futures = all.map do |workflow|
        Concurrent::Promises.future_on(::DatadogBackup::ThreadPool::TPOOL, workflow) do |wf|
          id = wf[id_keyname]
          get_and_write_file(id)
        end
      end

      watcher = ::DatadogBackup::ThreadPool.watcher
      watcher.join if watcher.status

      Concurrent::Promises.zip(*futures).value!
    end

    def get_by_id(id)
      workflow = get(id)
      # Remove timestamps from attributes before applying general banlist
      if workflow['attributes']
        workflow['attributes'] = workflow['attributes'].reject do |key, _|
          @banlist.include?(key)
        end
      end
      except(workflow)
    rescue Faraday::ResourceNotFound
      LOGGER.warn("Workflow #{id} not found (404)")
      {}
    rescue Faraday::BadRequestError => e
      LOGGER.warn("Workflow #{id} returned bad request (400) - skipping")
      {}
    end

    def initialize(options)
      super
      @banlist = %w[createdAt modifiedAt lastExecutedAt created_at modified_at last_executed_at].freeze
    end

    # v2 API wraps all responses in 'data' key
    def body_with_2xx(response)
      raise "#{caller_locations(1, 1)[0].label} failed with error #{response.status}" unless response.status.to_s =~ /^2/

      response.body.fetch('data')
    end

    # Override create to strip metadata fields that v2 API doesn't accept
    def create(body)
      clean_body = strip_metadata_fields(body)
      super(clean_body)
    end

    # Override update to use PATCH (v2 API requirement) and strip metadata fields
    def update(id, body)
      clean_body = strip_metadata_fields(body)
      LOGGER.debug "Updating workflow #{id} with body: #{clean_body.inspect}"
      headers = {}
      response = api_service.patch("/api/#{api_version}/#{api_resource_name}/#{id}", clean_body, headers)
      body = body_with_2xx(response)
      LOGGER.warn "Successfully restored #{id} to datadog."
      LOGGER.info 'Invalidating cache'
      @get_all = nil
      body
    end

    private

    # Remove fields that shouldn't be sent to the API for create/update
    def strip_metadata_fields(body)
      cleaned = body.reject { |key, _| %w[id relationships type].include?(key) }

      # Also remove timestamp fields from within attributes
      if cleaned['attributes']
        cleaned['attributes'] = cleaned['attributes'].reject do |key, _|
          %w[createdAt updatedAt modifiedAt lastExecutedAt created_at updated_at modified_at last_executed_at].include?(key)
        end
      end

      cleaned
    end

    def api_version
      'v2'
    end

    def api_resource_name
      'workflows'
    end

    def id_keyname
      'id'
    end
  end
end
