require 'httparty'
require 'json'

$firebase_url = "https://inf551-jordankm.firebaseio.com"

class QueriesController < ApplicationController
  def show
    databases_query = $firebase_url + '/.json?shallow=true'
    databases_response = HTTParty.get(databases_query)
    databases = JSON.parse(databases_response.body)
    @databases_list = databases.keys 


    @database_name = params["database_name"]
    @table_names = get_table_names()
    @query = params["db_query"]
    @query = @query.sub(".", "*")
    
    get_list_of_objs()

    sort_list_of_objs()
    puts " "
    puts "Sorted list"
    puts @obj_list


    @render_objects = get_render_objects()

    render :show
  end

  # Private methods


  # requests_per_table is a hash :  {table_name : [ { primary_key_column_name : [ primary_values ]} ,  ]}}
  def add_object_to_request_table(object, requests_per_table)
    if object == nil
      return
    end 

    table_name = nil
    primary_keys = nil
    object.each_key do |key|
      primary_keys = key.split(/;;/)
      inner_obj = object[key]
      inner_obj.each_key do |inner_key| 
        table_name = inner_key
      end
    end

    if not requests_per_table.has_key? table_name
      requests_per_table[table_name] = Array.new
    end

    request_list = requests_per_table[table_name]

    primary_columns = primary_columns_for_table(table_name)
    primary_keys.each_with_index do |primary_key, index|
      primary_column = primary_columns[index]

      added = false
      request_list.each do |request_hash|
        if request_hash.has_key? primary_column
          request_hash[primary_column].append(primary_key)
          added = true
        end
      end

      if not added
        request_obj = Hash.new
        request_obj[primary_column] = [primary_key]
        request_list.append(request_obj)
      end
    end

    puts "" 
    puts "requests per table: "
    puts requests_per_table
    puts ""


  end

  def primary_columns_for_table(table_name)
    return @table_schemas[table_name]["Primary Keys"]
  end

  def get_foreign_info_for_table(table_name)
    return @table_schemas[table_name]["foreign_info"]
  end
  
  def foreign_columns_for_table(table_name)
    foreign_info = @table_schemas[table_name]["foreign_info"]
    foreign_cols = Array.new
    foreign_info.each do |info|
      foreign_cols.append(info["Foreign key column"])
    end
    return foreign_cols
  end

  def get_foreign_val_for_object(object, table_name)
    foreign_cols = foreign_cols_for_table(table_name)
    foreign_vals = Array.new
    foreign_cols.each do |col|
      foreign_vals.append(object[col])
    end
    return foreign_vals.join(";;")
  end

  def get_primary_val_for_object(object, table_name)
    primary_cols = primary_columns_for_table(table_name)
    primary_vals = Array.new
    primary_cols.each do |col|
      primary_vals.append(object[col])
    end
    return primary_vals.join("_")
  end

  # requests_per_table is a hash :  {table_name : [ { primary_key_column_name : [ primary_values ] },  ]}}
  # make requests to firebase and create render objects (tables) from the responses
  def get_render_objects_from_request_table(requests_per_table)
    #query_string = $firebase_url + "/" + @database_name + "/schema.json?" 
    query_string = $firebase_url + "/" + @database_name + "/" 

    render_objs = []
    requests_per_table.each_key do |table_name|
      table_query = query_string + table_name + ".json?"
      primary_key_list = requests_per_table[table_name]

      request_hash = primary_key_list[0]
      request_hash.each_key do |primary_col|
        primary_vals = request_hash[primary_col]
        primary_vals.each_with_index do |primary_val, index|
          final_query = table_query + 'orderBy="' + primary_col + '"&equalTo="' + primary_val + '"'
          puts final_query
          response = HTTParty.get(final_query)
          response_obj = JSON.parse(response.body)
          #response_obj["Table Name"] = table_name
          puts "OBJECT FROM RESPONSE"
          puts response_obj
          object_to_append = nil
          response_obj.each_key do |response_key|
            #object_to_append = response_obj[response_key]
            object= response_obj[response_key]
            is_match = true
            primary_key_list.slice(1, primary_key_list.length - 1).each do |secondary_hash|
              secondary_hash.each_key do |secondary_col| 
                secondary_val = secondary_hash[secondary_col][index]
                val = object[secondary_col]
                if val != secondary_val
                  is_match = false
                  break
                end
              end
            end
            if is_match
              object_to_append = object
            end
          end

          if not object_to_append
            next
          end

          object_to_append["Table name"] = table_name

          hyperlinks = get_hyperlinks_for_object(object_to_append, table_name)
          if hyperlinks
            object_to_append["Hyperlinks"] = hyperlinks
          end
          render_objs.append(object_to_append)
        end

      end
    end

    puts ""
    puts "RENDER OBJS : "
    puts render_objs
    return render_objs
  end

  # hyperlinks should return a hash { foreign key column : hyperlink url }
  def get_hyperlinks_for_object(response_obj, table_name)
    foreign_info = get_foreign_info_for_table(table_name)
    if not foreign_info
      return nil
    end
    hyperlinks = Hash.new
    table_hash = Hash.new
    cols_hash = Hash.new

    foreign_info.each do |info|
      foreign_col = info["Foreign key column"]
      foreign_table = info["Foreign table name"]
      foreign_table_col = info["Foreign table column"]
      foreign_val = response_obj[foreign_col]

      if foreign_val == "None"
        next
      end

      if not table_hash.has_key? foreign_table
        table_hash[foreign_table] = Array.new
        cols_hash[foreign_table] = Array.new
      end
      table_hash[foreign_table].append(foreign_val)
      cols_hash[foreign_table].append(foreign_table_col)
    end

    foreign_info.each do |info|
      foreign_col = info["Foreign key column"]
      foreign_table = info["Foreign table name"]
      foreign_val = response_obj[foreign_col]

      if foreign_val == "None"
        next
      end
      if not table_hash.has_key? foreign_table
        next
      end
      
      foreign_vals = table_hash[foreign_table].join(";;") 
      foreign_cols = cols_hash[foreign_table].join(";;")
      hyperlinks[foreign_col] = ("/table_query?table_name=" + foreign_table +  "&primary_vals=" + foreign_vals +
                                 "&prev_table=" + table_name + "&primary_columns=" + foreign_cols + "&db_name=" + @database_name)
    end


    return hyperlinks

  end

  
  def get_render_objects
    @table_schemas = get_table_schemas()
    puts "table schemas : "
    puts @table_schemas

    requests_per_table = Hash.new
    @obj_list.each do |object|
      add_object_to_request_table(object, requests_per_table)
    end


    return get_render_objects_from_request_table(requests_per_table)
  end


  def get_table_schemas
    query_string = $firebase_url + "/" + @database_name + "/schema.json?" 
    response = HTTParty.get(query_string)
    response_obj = JSON.parse(response.body)
    return response_obj
  end


  
  def sort_list_of_objs
    if @obj_list.empty?
      return
    end

    @obj_list.sort! do |a, b|
      if (a == nil or b == nil)
        return a <=> b
      end
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
    tokens =  @query.split(/,|-| /)
    lower_tokens = Array.new
    tokens.each do |token|
      lower_tokens.append(token.downcase)
    end
    return lower_tokens
  end


  # response is a list of objects
  # we return an object in the form { primary key value : { table_name : [ list of cols] }}
  def make_table_object_from_response(responses, token, table_name, objects)
    responses.each do |response|
      object = Hash.new
      should_append = true
      puts "PRIMARY VALUES : "
      puts response["Primary Values"]
      primary_key_value = response["Primary Values"].join(";;")
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
        puts "Token = "
        puts token
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
    return @obj_list
  end


end
