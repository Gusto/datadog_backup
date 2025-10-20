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
      except(get(id))
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

    private

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
