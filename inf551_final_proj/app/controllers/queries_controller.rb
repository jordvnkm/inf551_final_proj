require 'httparty'
require 'json'

$firebase_url = "https://inf551-jordankm.firebaseio.com"

class QueriesController < ApplicationController
  def show
    @database_name = params["database_name"]
    @table_names = get_table_names()
    @query = params["db_query"]
    
    @list_of_objs = get_list_of_objs()

    render :show
  end

  # Private methods

  def get_table_names
    query_string = $firebase_url + "/" + @database_name + "/index.json?shallow=true" 
    response = HTTParty.get(query_string)
    response_obj = JSON.parse(response.body)
    return response_obj.keys
  end

  def get_tokens
    return @query.split(/,|-| /)
  end


  # response is a list of objects
  # we return an object in the form { primary key value : { table_name : [ list of cols] }}
  def make_table_object_from_response(responses, token, table_name)
    object = Hash.new
    responses.each do |response|
      primary_key_value = response["Primary Values"].join("_")
      puts primary_key_value
      if not object.has_key? primary_key_value
        object[primary_key_value] = Hash.new
      end

      inner_object = object[primary_key_value]
      if not inner_object.has_key? table_name
        inner_object[table_name] = Array.new
      end

      inner_object[table_name].append(response["Column"])
    end
    return object
  end



  def get_list_for_table(table_name)
    puts "table name = " + table_name
    tokens = get_tokens()
    objects = Array.new
    tokens.each do |token|
      puts "token = " + token
      query_string = $firebase_url + "/" + @database_name + "/index/" + table_name + "/" + token + ".json?"
      response = HTTParty.get(query_string)
      response_obj = JSON.parse(response.body)
      if (response_obj)
        objects = objects.append(make_table_object_from_response(response, token, table_name))
      else
        puts "Empty response"
      end
    end
    puts objects
    return objects
  end
  
  def get_list_of_objs
    obj_list = Array.new
    @table_names.each do |table_name|
      obj_list = obj_list.concat(get_list_for_table(table_name))
    end

    ###### TODO NEED TO SORT THE LIST OF OBJECTS NOW
    return obj_list
  end


end
