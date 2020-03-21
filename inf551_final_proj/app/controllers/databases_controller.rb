require 'httparty'
require 'json'

$firebase_url = 'https://inf551-jordankm.firebaseio.com'

class DatabasesController < ApplicationController
  def show
    databases_query = $firebase_url + '/.json?shallow=true'
    databases_response = HTTParty.get(databases_query)
    databases = JSON.parse(databases_response.body) 
    @databases_list = databases.keys

    render :show
  end

end
