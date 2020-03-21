import mysql.connector
import requests
import sys
import re
import json
import csv
from decimal import Decimal

FIREBASE_URL = "https://inf551-jordankm.firebaseio.com/"

def remove_special_chars(string):
    return ''.join(e for e in string if e.isalnum() or e == "_")


# returns a string to query the database for its schema
def get_table_schema_str(database_name, table_name):
    string = """SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = '%s' AND TABLE_NAME = '%s';""" % (database_name, table_name)
    return string

# Returns a string to query the database for all rows in the table
def get_table_row_str(database_name, table_name):
    string = """SELECT *
    FROM %s;""" % (table_name)
    return string

def get_foreign_key_str(database_name, table_name):
    string = """
    SELECT
      TABLE_NAME,COLUMN_NAME,CONSTRAINT_NAME, REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME
    FROM
      INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE
      TABLE_SCHEMA = '%s' AND
      TABLE_NAME = '%s' AND
      REFERENCED_TABLE_NAME != 'NULL';""" % (database_name, table_name)
    return string

# returns a string to query the database to get the primary key
def get_primary_key_str(database_name, table_name):
    string = """SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = '%s'
    AND TABLE_NAME = '%s'
    AND COLUMN_KEY = 'PRI';""" % (database_name, table_name)
    return string
    
# inverted index should be a dict from keyword -> list of objects
# each value object should be dict with:
    # (primarykey: primarykeyval,
    # columnname: columnameval,
    # tablename: tablenameval,
    # foreignkeycolumnNames: [list of columnnames])
def send_inverted_index_to_firebase(inverted_index, firebase_nodename, table_name):
    firebase_url = FIREBASE_URL + firebase_nodename + "/index/" + str(table_name) + ".json"
    #x = requests.patch(firebase_url, data=json.dumps(inverted_index))
    #print("sending inverted index")
    #x = requests.put(firebase_url, data=json.dumps(inverted_index))
    #print(x)
    #return

    temp_index = {}
    for key in inverted_index.keys():
        temp_index[str(key)] = inverted_index[key]
        if (sys.getsizeof(temp_index) > 10000):
            print("Writing index 1")
            x = requests.patch(firebase_url, data=json.dumps(temp_index))
            print(x)
            temp_index.clear()

    if (len(temp_index) > 0):
        print("writing index 2")
        x = requests.patch(firebase_url, data=json.dumps(temp_index))
        print(x)

    #x = requests.put(firebase_url, data=json.dumps(inverted_index))
    #print(x)


# tokenizes a column value. should be delimitted by whitespace and hyphen)
# also make it lowercase
def tokenize(value):
    if not type(value) == str:
        return [value]
    values = re.split(r'[-\s]\s*', value)
    values = [remove_special_chars(string) for string in values]
    values = [str(val).lower() for val in values]

    return values


# returns an inverted index value object for a given token
def to_inverted_index_value_obj(foreign_keys, foreign_key_values,
        foreign_table_vals, primary_keys, primary_key_values, table_name, column_name):
    obj = {"Table Name": table_name, "Column": column_name}
#    if (len(foreign_keys) > 0):
#        obj["Foreign Columns"] = foreign_keys
#        obj["Foreign Values"] = foreign_key_values
#        obj["Foreign Tables"] = foreign_table_vals

    if (len(primary_keys) > 0):
        obj["Primary Columns"] = primary_keys
        obj["Primary Values"] = primary_key_values
    else:
        return None
    return obj


    #return {"Primary Columns" : primary_keys, "Primary Values": primary_key_values, "Foreign  Columns": foreign_keys  , 
    #        "Foreign Values": foreign_key_values, "Foreign Tables": foreign_table_vals, "Table Name": table_name,
    #        "Column": column_name}
    

def send_table_schema_to_firebase(firebase_nodename, table_name, primary_keys, foreign_key_columns, foreign_table_vals):
    firebase_url = FIREBASE_URL +  firebase_nodename + "/schema.json"

    # table_schema will hold a json like dict representing the table schema.
    table_schema = {}
    table_schema[table_name] = {"Primary Keys": primary_keys}

    foreign_info = []
    for index in range(len(foreign_key_columns)): # could also use foreign_table_vals
        foreign_key_column = foreign_key_columns[index]
        foreign_table_val = foreign_table_vals[index]
        foreign_info.append({
            "Foreign key column": foreign_key_column,
            "Foreign table name": foreign_table_val
            })
    table_schema[table_name]["foreign_info"] = foreign_info
    print("schema request")
    x = requests.patch(firebase_url, data=json.dumps(table_schema, indent=4, separators=(',', ': ')))
    print(x.text)


def add_rows_to_inverted_index(columns , rows, foreign_keys, primary_keys, inverted_index, database_name, table_name, firebase_nodename):
    if len(columns) != len(rows[0]):
        print(str(columns))
        print(str(rows))
        print("attributes and columns do not match length \n")

    primary_key_columns = []
    foreign_key_columns = []
    foreign_key_indexes = []
    foreign_table_vals = []
    
    for key in primary_keys:
        primary_key_columns.append(primary_keys.index(key))

    # foreign keys is a tuple of info
    # [current table, foreign col,  etc  TODO ]
    for key_tuple in foreign_keys:
        foreign_key_indexes.append(columns.index(key_tuple[1]))
        foreign_table_vals.append(key_tuple[3])
        foreign_key_columns.append(key_tuple[1])

   
    send_table_schema_to_firebase(firebase_nodename, table_name, primary_keys, foreign_key_columns, foreign_table_vals)

    for row in rows:
        primary_key_values = [row[i] for i in primary_key_columns]
        foreign_key_values = [row[i] for i in foreign_key_indexes]

        for index in range(len(columns)):
            column_name = columns[index]
            column_val = row[index]
            column_values = tokenize(column_val)
            for token in column_values:
                index_obj = to_inverted_index_value_obj(foreign_key_columns, foreign_key_values, foreign_table_vals,
                    primary_keys, primary_key_values, table_name, column_name)
                if index_obj is not None:
                    if token == None or token == "":
                        continue
                    if token not in inverted_index:
                        inverted_index[token] = []
                    inverted_index[token].append(index_obj)


def remove_duplicates_from_list(mylist):
    seen = set()
    seen_add = seen.add
    return [x for x in mylist if not (x in seen or seen_add(x))]

# updates firebase database indexing rules
def update_firebase_indexing_rules(primary_keys, firebase_nodename, table_name):
    if (len(primary_keys) == 0):
        return
    data = requests.get(
            'https://inf551-jordankm.firebaseio.com/.settings/rules.json?auth=hfuGYtYULnO7qXd9PcWDnoIQ5kUmvzvPoXfxyJmc')
    data_str = data.text
    data = json.loads(data_str)
    rules_dict = data["rules"]
    nodename_rules = {}
    if firebase_nodename in rules_dict:
        nodename_rules = rules_dict[firebase_nodename]
    
    table_rules = {}
    if table_name in nodename_rules:
        table_rules  = nodename_rules[table_name]

    indexOn_list = []
    if ".indexOn" in table_rules:
        indexOn_list = table_rules[".indexOn"]
    for primary_key in primary_keys:
        indexOn_list.append(primary_key)

    indexOn_list = remove_duplicates_from_list(indexOn_list)
    table_rules[".indexOn"] = indexOn_list
    nodename_rules[table_name] =  table_rules
    rules_dict[firebase_nodename] = nodename_rules

    x = requests.put('https://inf551-jordankm.firebaseio.com/.settings/rules.json?auth=hfuGYtYULnO7qXd9PcWDnoIQ5kUmvzvPoXfxyJmc',
            data=json.dumps(data, indent=4, separators=(',', ': ')))


# sends the table to firebase. each item should be keyed by primary key
def send_table_to_firebase(columns, rows, foreign_keys, primary_keys, inverted_index,
        database_name, table_name, firebase_nodename):
    #firebase_url = FIREBASE_URL + firebase_nodename + "/" + table_name + ".json?writeSizeLimit=unlimited"
    #print("DELETING OLD DATA")
    #x = requests.delete(firebase_url)
    #print(x)
    column_list = []
    for column in columns:
        col = remove_special_chars(column)
        column_list.append(col)

    parsed_rows = []
    for row in rows:
        parsed_row = []
        for item in row:
            if type(item) == Decimal:
                parsed_row.append(str(float(item)))
            else:
                parsed_row.append(str(item))
        parsed_rows.append(parsed_row)

    add_rows_to_inverted_index(column_list, parsed_rows, foreign_keys, primary_keys, inverted_index, database_name, table_name, firebase_nodename)

    table_dict = {}
    row_index = 0
    for row in parsed_rows:
        table_item = {}
        for index in range(len(column_list)):
            attribute = row[index]
            col_val = column_list[index] 
            table_item[col_val] = attribute

        table_dict[row_index] = table_item
        if (sys.getsizeof(table_dict) > 100000):
            print("sending table1")
            firebase_url = FIREBASE_URL + firebase_nodename + "/" + table_name + ".json"
            x = requests.patch(firebase_url, data=json.dumps(table_dict))
            print(x)
            table_dict.clear()
        row_index += 1

    if (len(table_dict) > 0):
        print("sending table2")
        firebase_url = FIREBASE_URL + firebase_nodename + "/" + table_name + ".json"
        x = requests.patch(firebase_url, data=json.dumps(table_dict))
        print(x)


    return
    
    
    #firebase_url = FIREBASE_URL + firebase_nodename + "/" + table_name + ".json?writeSizeLimit=unlimited"
    firebase_url = FIREBASE_URL + firebase_nodename + "/" + table_name + ".json"
    print("WRITING DATA")
    x = requests.put(firebase_url, data=json.dumps(table_dict))
    print(x)

    #firebase_url = FIREBASE_URL + firebase_nodename + ".json"
    #x = requests.put(firebase_url, data=json.dumps({table_name : table_items}))
    #print(x.text)
    
    update_firebase_indexing_rules(primary_keys, firebase_nodename, table_name)


def batch_send_table(firebase_nodename, table_name, table_dict):         
    firebase_url = FIREBASE_URL + firebase_nodename + "/" + table_name + ".json"
    x = requests.put(firebase_url, data=json.dumps(table_dict))
    print(x.text)


def get_table_columns(cursor, database_name, table_name):
    query = "select * from %s.%s;" % (database_name, table_name)
    cursor.execute(query)
    rows = cursor.fetchall()

    column_names = [i[0] for i in cursor.description]
    return column_names

def get_foreign_key_columns(cursor, database_name, table_name):
    query = get_foreign_key_str(database_name, table_name)

    cursor.execute(query)
    foreign_keys = cursor.fetchall()

    foreign_key_list = []
    for row in foreign_keys:
        foreign_key_list.append([remove_special_chars(item) for item in row])
        #foreign_key_list.append(row)

    return foreign_key_list

def get_primary_key_columns(cursor, database_name, table_name):
    query = get_primary_key_str(database_name, table_name)

    cursor.execute(query)
    primary_keys = cursor.fetchall()

    primary_key_list = []
    for col in primary_keys:
        primary_key_list.append(remove_special_chars(col[0]))
    return primary_key_list

# cursor has executed table_query_string 
def add_table_to_firebase(cursor, database_name, table_name, inverted_index, firebase_nodename):
    columns = get_table_columns(cursor, database_name, table_name)

    table_row_query_string = get_table_row_str(database_name, table_name)
    cursor.nextset()
    cursor.execute(table_row_query_string)
    rows = cursor.fetchall()

    foreign_keys = get_foreign_key_columns(cursor, database_name, table_name)
    primary_keys = get_primary_key_columns(cursor, database_name,  table_name)
    #print(primary_keys)

    send_table_to_firebase(columns, rows, foreign_keys, primary_keys,
            inverted_index, database_name, table_name, firebase_nodename)


# main function. connects to mysql and correct DB.
# Queries tables and uses tables schema to add data to firebase
def import_databases(args):
    database_name = args[1]
    firebase_nodename = args[2]
    #inverted_index = {}
    
    cnx = mysql.connector.connect(user='root', password='Kiyoshi6',
                                  host='127.0.0.1', auth_plugin='mysql_native_password')
    cursor = cnx.cursor()
    use_database = "use " + database_name + ";"
    cursor.execute(use_database)
    cursor.execute("show tables;")
    table_names = cursor.fetchall()

    for table_name in table_names:
        table_name = table_name[0]
#        if table_name != "staff":
#            print("skipping")
#            continue
        inverted_index = {}
        add_table_to_firebase(cursor, database_name, table_name, inverted_index, firebase_nodename)
        send_inverted_index_to_firebase(inverted_index, firebase_nodename, table_name)
        #return


    #send_inverted_index_to_firebase(inverted_index, firebase_nodename)
    cnx.close()


if __name__ == "__main__":
    import_databases(sys.argv)


##########################################3
# tables to CSV
# csv to firebase (same as hw, including inverted index)
# include the different foreign keys in the inverted index

# to get foreign keys for a table
# foreign key column name will be "column_name"
# other table that is pointed to will be "referenced_table_name"
# other table primary key will be "referenced_column_name"


