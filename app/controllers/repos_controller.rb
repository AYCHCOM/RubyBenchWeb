class ReposController < ApplicationController
  before_action :find_organization_by_name
  before_action :find_organization_repo_by_name

  include JSONGenerator

  def index
    @charts =
      if charts = $redis.get("sparklines:#{@repo.id}")
        JSON.parse(charts).with_indifferent_access
      else
        @repo.generate_sparkline_data
      end
  end

  def show
    display_count = params[:display_count].to_i

    @benchmark_run_display_count =
      if BenchmarkRun::PAGINATE_COUNT.include?(display_count)
        display_count
      else
        BenchmarkRun::DEFAULT_PAGINATE_COUNT
      end

    if (@form_result_type = params[:result_type]) &&
       (@benchmark_type = find_benchmark_type_by_category(@form_result_type))

      # read versions from cache since it's shared among all `@charts`
      version_cache_key = "charts:#{@benchmark_type.id}:#{@benchmark_run_display_count}"
      versions = $redis.get(version_cache_key)
      @versions = JSON.parse(versions) if versions

      versions_calculate_cache = ActiveSupport::OrderedHash.new

      # `@benchmark_type` is the name of the benchmark - ex. 'Liquid parse', 'Optcarrot Lan_Master.nes'
      # Each `@benchmark_type` can have >= 1 `benchmark_result_type`s, which are the names of the metrics that
      #   the benchmark measures - ex. for 'Liquid parse', its `benchmark_result_type`s are 'Number of iterations per second'
      #   and 'Allocated objects'
      # Here, we are generating a chart for each of this benchmark's result types
      @charts = @benchmark_type.benchmark_result_types.map do |benchmark_result_type|
        cache_key = "#{BenchmarkRun.charts_cache_key(@benchmark_type, benchmark_result_type)}:#{@benchmark_run_display_count}"

        if versions && columns = $redis.get(cache_key)
          [JSON.parse(columns).symbolize_keys!, benchmark_result_type]
        else
          benchmark_runs = BenchmarkRun.fetch_commit_benchmark_runs(
            @form_result_type, benchmark_result_type, @benchmark_run_display_count
          )

          next if benchmark_runs.empty?

          chart_builder = ChartBuilder.new(benchmark_runs.sort_by do |benchmark_run|
            benchmark_run.initiator.created_at
          end)

          # Sample `columns` object (not exactly the same, but in this structure
          # 
          # {  
          #   columns: "[{\"name\": \"ab_bench\", \"data\": [1.23, 1.23]}]",
          #   categories: "[
          #     \"Commit: b6589fc
          #     Commit Date: 2017-02-09 20:56:19 UTC
          #     Commit Message: fix something
          #     ruby 2.2.0dev\", 
          #
          #     \"Commit: 356a192
          #     Commit Date: 2017-02-09 20:56:20 UTC
          #     Commit Message: fix something
          #     ruby 2.2.0dev\"
          #   ]"
          # }
          #
          # columns[:columns] is a JSON string with the benchmark name and datapoints (ie. columns of data)
          # columns[:categories] is a stringified JSON array with the versions that pop up when you hover over datapoints in the charts,
          #   where each element is an HTML string (ie. category of each column)
          #
          # ChartBuilder::build_columns returns a hash with keys :columns, :categories 
          # The return value of this do block becomes the value for the :categories
          columns = chart_builder.build_columns do |benchmark_run|
            environment = YAML.load(benchmark_run.environment)

            commit = benchmark_run.initiator

            # `version` is a JSON-friendly variation of the HTML strings in `columns[:categories]`
            # Multiple HTML-converted `version`s make up `columns[:categories]`
            version = {
              commit: commit.sha1[0..6],
              commit_date: commit.created_at,
              commit_message: commit.message.truncate(30)
            }
            # If there is more information about the environment, we add it to `version` 
            if environment.is_a?(Hash)
              # Use the key(s) in `environment` instead of setting `version[:environment]`
              version.merge!(environment)
              # Solely for the purpose of generating the correct HTML for `columns[:categories]`
              environment = hash_to_html(environment)
            else
              # If `environment` is not a Hash, then it is not JSON friendly, so we need to make
              #   a new key in `version`
              version[:environment] = environment
            end

            # Map each commit to its `version` object
            versions_calculate_cache[version[:commit]] ||= version

            # Generate HTML to store in `columns[:categories]`
            "Commit: #{version[:commit]}<br>" \
            "Commit Date: #{version[:commit_date]}<br>" \
            "Commit Message: #{version[:commit_message]}<br>" \
            "#{environment}"
          end
          # We mapped commits to `version` objects, but in the end we only want the `version`
          #   objects - this is why `versions_calculate_cache` is an ordered hash
          @versions ||= versions_calculate_cache.values

          $redis.set(cache_key, columns.to_json)
          # cache the `@versions` as well
          $redis.set(version_cache_key, @versions.to_json)
          [columns, benchmark_result_type]
        end
      end.compact
    end

    respond_to do |format|
      format.html do
        @result_types = fetch_categories
      end
      format.json { render json: generate_json(@charts, @versions, params) }
      format.js
    end
  end

  def show_releases
    if (@form_result_type = params[:result_type]) &&
       (@benchmark_type = find_benchmark_type_by_category(@form_result_type))

      versions_calculate_cache = ActiveSupport::OrderedHash.new
      @charts = @benchmark_type.benchmark_result_types.map do |benchmark_result_type|
        benchmark_runs = BenchmarkRun.fetch_release_benchmark_runs(
          @form_result_type, benchmark_result_type
        )

        next if benchmark_runs.empty?
        benchmark_runs = BenchmarkRun.sort_by_initiator_version(benchmark_runs)

        if latest_benchmark_run = BenchmarkRun.latest_commit_benchmark_run(@benchmark_type, benchmark_result_type)
          benchmark_runs << latest_benchmark_run
        end

        columns = ChartBuilder.new(benchmark_runs).build_columns do |benchmark_run|
          environment = YAML.load(benchmark_run.environment)

          # generate the version object
          config = { version: benchmark_run.initiator.version }
          if environment.is_a?(Hash)
            # use the key(s) in `environment` instead of setting `config[:environment`]
            config.merge!(environment)
            # solely for the purpose of generating the correct HTML
            environment = hash_to_html(environment)
          else
            config[:environment] = environment
          end

          versions_calculate_cache[config[:version]] ||= config

          # generate HTML
          "Version: #{config[:version]}<br>" \
          "#{environment}"
        end
        @versions ||= versions_calculate_cache.values

        [columns, benchmark_result_type]
      end.compact
    end

    respond_to do |format|
      format.html do
        @result_types = fetch_categories
      end
      format.json { render json: generate_json(@charts, @versions, params) }
      format.js
    end
  end

  private

  def find_organization_by_name
    @organization = Organization.find_by_name(params[:organization_name]) || not_found
  end

  def find_organization_repo_by_name
    @repo = @organization.repos.find_by_name(params[:repo_name]) || not_found
  end

  def find_benchmark_type_by_category(category)
    @repo.benchmark_types.find_by_category(category)
  end

  def fetch_categories
    @repo.benchmark_types.pluck(:category)
  end

  # Generate an HTML string representing the `hash`, with each pair on a new line
  def hash_to_html(hash)
    hash.map do |k, v|
      "#{k}: #{v}" 
    end.join("<br>")
  end
end
