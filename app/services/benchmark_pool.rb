module BenchmarkPool
  def self.enqueue(repo_name, commit_sha, organization = nil)
    case repo_name
    when 'ruby'
      RemoteServerJob.perform_later(commit_sha, 'ruby_trunk', organization: organization || 'ruby')
      # RemoteServerJob.perform_later(commit_sha, 'ruby_trunk_discourse')
    when 'rails'
      RemoteServerJob.perform_later(commit_sha, 'rails_trunk', organization: organization || 'rails')
    else
      raise ArgumentError, "unknown repo: #{repo_name}"
    end
  end
end
