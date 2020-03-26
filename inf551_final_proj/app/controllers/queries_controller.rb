require 'httparty'
require 'json'

$firebase_url = "https://inf551-jordankm.firebaseio.com"

class QueriesController < ApplicationController
  def show
    @database_name = params["database_name"]
    @table_names = get_table_names()
    @query = params["db_query"]
    
    get_list_of_objs()

    @list_of_objs = sort_list_of_objs()
    puts " "
    puts "Sorted list"
    puts @list_of_objs

    render :show
  end

  # Private methods
  
  def sort_list_of_objs
    return @obj_list.sort do |a, b|
      puts "SORTING"
      cols_a = nil
      cols_b = nil
      a.each_key do |akey|
        inner_a = a[akey]
        inner_a.each_key do |ainner|
          cols_a = inner_a[ainner]
        end
      end
      b.each_key do |bkey|
        inner_b = b[bkey]
        inner_b.each_key do |binner|
          cols_b = inner_b[binner]
        end
      end
      puts cols_a
      puts cols_b
      if cols_a.length > cols_b.length
        -1
      elsif cols_a.length < cols_b.length 
        1
      else
        len_a = cols_a.uniq().length() 
        len_b = cols_b.uniq().length() 
        len_a <=> len_b
      end
    end
  end

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
  def make_table_object_from_response(responses, token, table_name, objects)
    responses.each do |response|
      object = Hash.new
      should_append = true
      primary_key_value = response["Primary Values"].join("_")
      puts primary_key_value

      # find object if it already exists in the object list.
      objects.each do |obj|
        if obj.has_key? primary_key_value
          should_append = false
          object = obj
        end
      end

      if not object.has_key? primary_key_value
        object[primary_key_value] = Hash.new
      end

      inner_object = object[primary_key_value]
      if not inner_object.has_key? table_name
        inner_object[table_name] = Array.new
      end

      inner_object[table_name].append(response["Column"])
      if should_append
        objects.append(object)
      end
    end
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
        puts "Response = "
        puts response_obj
        puts " "
        make_table_object_from_response(response_obj, token, table_name, objects)
      else
        puts "Empty response"
      end
    end
    @obj_list.concat(objects)
  end

  def get_list_of_objs
    @obj_list = Array.new
    @table_names.each do |table_name|
      get_list_for_table(table_name)
    end
    temp = @obj_list[0]
    @obj_list[0] = @obj_list[2]
    @obj_list[2] = temp
    puts @obj_list
    return @obj_list

  end


end
