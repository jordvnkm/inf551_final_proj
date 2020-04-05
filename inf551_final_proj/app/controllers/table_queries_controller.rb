require 'httparty'
require 'json'

$firebase_url = 'https://inf551-jordankm.firebaseio.com'


class TableQueriesController < ApplicationController
  def show
    @database_name = params["db_name"]
    @table_name = params["table_name"]
    @primary_key = params["primary_vals"]
    @primary_columns = params["primary_columns"]

    @render_object = get_render_object()
    puts "render object : "
    puts @render_object


    #render plain: params
    render :show

  end

  # Private methods

  def get_table_schema
    query = $firebase_url + "/" + @database_name + "/schema/" + @table_name + ".json"
    response = HTTParty.get(query)
    response_obj = JSON.parse(response.body)
    return response_obj
  end

  def get_object_from_firebase
    primary_keys = @primary_key.split(";;")
    new_primary_keys = Array.new
    primary_keys.each do |key|
      new_primary_keys.append(key.sub(".", "*"))
    end
    primary_keys = new_primary_keys
    
    primary_cols = @primary_columns.split(";;")
    query = ($firebase_url + "/" + @database_name + "/" + @table_name + ".json?orderBy=" + '"' + primary_cols[0] +
             '"' + "&equalTo=" + '"' +  primary_keys[0] + '"')
    response = HTTParty.get(query)
    response_obj = JSON.parse(response.body)

    match = nil
    response_obj.each_key do |record_num|
      record = response_obj[record_num]
      matched = true
      primary_cols.each_with_index do |col, index|
        primary_val = primary_keys[index]
        puts "PRIMARY VAL"
        puts primary_val
        puts "RECORD VAL"
        puts record[col]
        if record[col] != primary_val
          matched = false
          next
        end
      end

      if matched
        puts "MATCHED"
        match = record
      end
    end

    return match
  end


  # hyperlinks should be a hash {foreign key column : hyperlink url}
  def add_hyperlinks_to_object(object)
    foreign_info = @table_schema["foreign_info"]
    if not foreign_info or not object
      return object
    end

    hyperlinks = Hash.new
    table_hash = Hash.new
    cols_hash = Hash.new

    foreign_info.each do |info|
      foreign_col = info["Foreign key column"]
      foreign_table = info["Foreign table name"]
      foreign_table_col = info["Foreign table column"]
      foreign_val = object[foreign_col]

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
      foreign_table_col = info["Foreign table column"]
      foreign_val = object[foreign_col]

      if foreign_val == "None"
        next
      end

      if not table_hash.has_key? foreign_table
        next
      end
      #foreign_val = object[foreign_col]
      foreign_vals = table_hash[foreign_table].join(";;")
      foreign_cols = cols_hash[foreign_table].join(";;")
      hyperlinks[foreign_col] = (
        "/table_query?table_name=" + foreign_table + "&primary_vals=" + foreign_vals + "&prev_table=" +
        @table_name + "&primary_columns=" + foreign_cols + "&db_name=" + @database_name
      )
    end
    object["Hyperlinks"] = hyperlinks
    return object

  end

  def get_render_object
    @table_schema = get_table_schema()
    puts @table_schema

    object = get_object_from_firebase()
    if not object
      return
    end
    object = add_hyperlinks_to_object(object)
    object["Table name"] = @table_name
    return object

  end
end
