class TableQueriesController < ApplicationController
  def show
    render plain: params

  end
end
