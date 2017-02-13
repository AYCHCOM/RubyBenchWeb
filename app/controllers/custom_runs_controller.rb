class CustomRunsController < AdminController
  def new
  end

  def create
    params = custom_run_params
    # render plain: [params[:organization], params[:repo], params[:commit]]
    #BenchmarkPool.enqueue(params[:repo], params[:commit])
    
    # get commit message from github api
    uri = URI.parse("https://api.github.com/repos/#{params[:organization]}/#{params[:repo]}/git/commits/#{params[:commit]}")
    req = Net::HTTP::Get.new(uri)
    req.add_field("Authorization", "token #{ENV['GITHUB_API_TOKEN']}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = http.request(req)

    render status: 500 unless res.kind_of?(Net::HTTPSuccess)

    organization = Organization.find_or_create_by!(name: params[:organization], url: "https://github.com/#{params[:organization]}")
    repo = Repo.find_or_create_by!(name: params[:repo], organization_id: organization.id, url: "https://github.com/#{params[:organization]}/#{params[:repo]}")
    body = JSON.parse(res.body, symbolize_names: true)
    commit_hash = {
      sha1: params[:commit],
      url: "https://github.com/#{params[:organization]}/#{params[:repo]}/commit/#{params[:commit]}",
      message: body[:message].truncate(30),
      timestamp: body[:committer][:date]
    }

    puts commit_hash

    if create_commit(commit_hash, repo.id)
      BenchmarkPool.enqueue(params[:repo], params[:commit], params[:organization])
    end

    redirect_to custom_runs_path
  end

  private
  def custom_run_params
    params.require(:custom_run).permit(:organization, :repo, :commit)
  end

  def create_commit(commit, repo_id)
    Commit.find_or_create_by(sha1: commit[:sha1]) do |c|
      c.url = commit[:url]
      c.message = commit[:message]
      c.repo_id = repo_id
      c.created_at = commit[:timestamp]
    end
  end
end
