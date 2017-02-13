class CustomRunsController < AdminController
  def new
  end

  def create
    params = custom_run_params
    # render plain: [params[:organization], params[:repo], params[:commit]]
    BenchmarkPool.enqueue(params[:repo], params[:commit])
    redirect_to custom_runs_path
  end

  private
  def custom_run_params
    params.require(:custom_run).permit(:organization, :repo, :commit)
  end
end
