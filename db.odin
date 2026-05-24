package main

import "core:c"
import "core:encoding/uuid"
import "core:strings"
import sqlite "vendor/odin-sqlite3"

connect :: proc() -> (^sqlite.Connection, sqlite.Result_Code) {
	db: ^sqlite.Connection = nil
	if rc := sqlite.open("./db.sqlite", &db); rc != .Ok {
		return nil, rc
	}
	return db, .Ok
}

create_tables :: proc(db: ^sqlite.Connection) {
	credential_table_sql: cstring = `
		CREATE TABLE IF NOT EXISTS credentials (
		    id TEXT PRIMARY KEY,
		    auth_type TEXT NOT NULL
		        CHECK(auth_type IN (
		            'password',
		            'ssh',
		            'token',
		            'keypair'
		        )),
		    secret_key TEXT NOT NULL
		);`

	if sqlite.exec(db, credential_table_sql, nil, nil, nil) != .Ok {
		panic("exec failed")
	}

	connection_table_sql: cstring = `
		CREATE TABLE IF NOT EXISTS connections (
		    id TEXT PRIMARY KEY,
		    name TEXT NOT NULL,
		    db_type TEXT NOT NULL
		        CHECK(db_type IN (
		            'postgres',
		            'sqlite',
		            'mysql',
		            'mssql'
		        )),

		    host TEXT,
		    port INTEGER,
		    database_name TEXT,
		    username TEXT,

		    ssl_enabled INTEGER NOT NULL DEFAULT 0,
		    credential_id TEXT,
		    color TEXT,
		    icon TEXT,
		    is_favorite INTEGER DEFAULT 0,

		    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
		    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
		    last_connected_at TEXT DEFAULT CURRENT_TIMESTAMP,

		    FOREIGN KEY (credential_id) REFERENCES credentials(id)
		);`

	if sqlite.exec(db, connection_table_sql, nil, nil, nil) != .Ok {
		panic("exec failed")
	}

	query_history_sql: cstring = `
		CREATE TABLE IF NOT EXISTS query_history (
		    id TEXT PRIMARY KEY,
		    connection_id TEXT NOT NULL,
		    sql TEXT NOT NULL,
		    executed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
		    duration_ms INTEGER,
		    succeeded INTEGER,
		    FOREIGN KEY (connection_id) REFERENCES connections(id)
		);`

	if sqlite.exec(db, query_history_sql, nil, nil, nil) != .Ok {
		panic("exec failed")
	}

	tabs_sql: cstring = `
		CREATE TABLE IF NOT EXISTS tabs (
		    id TEXT PRIMARY KEY,
		    connection_id TEXT,
		    title TEXT,
		    sql TEXT,
		    sort_order INTEGER,
		    FOREIGN KEY (connection_id) REFERENCES connections(id)
		);`

	if sqlite.exec(db, tabs_sql, nil, nil, nil) != .Ok {
		panic("exec failed")
	}
}

Connection :: struct {
	id:                string,
	name:              string,
	db_type:           string,
	host:              ^string,
	port:              ^int,
	database_name:     ^string,
	username:          ^string,
	sql_enabled:       int,
	credential_id:     ^string,
	color:             ^string,
	icon:              ^string,
	is_favorite:       int,
	created_at:        string,
	updated_at:        string,
	last_connected_at: ^string,
}

SQLite_Datatypes :: enum {
	INTEGER = 1,
	FLOAT   = 2,
	TEXT    = 3,
	BLOB    = 4,
	NULL    = 5,
}


get_connections :: proc(db: ^sqlite.Connection) -> []Connection {
	sql: cstring = `
		SELECT
			id,
			name,
			db_type,
			host,
			port,
			database_name,
			username,
			ssl_enabled,
			credential_id,
			color,
			icon,
			is_favorite,
			created_at,
			updated_at,
			last_connected_at
		FROM connections`

	stmt: ^sqlite.Statement
	if sqlite.prepare_v2(db, sql, -1, &stmt, nil) != .Ok {
		panic("prepare failed")
	}
	defer sqlite.finalize(stmt)

	connections: [dynamic]Connection

	for sqlite.step(stmt) == .Row {
		conn := Connection{}
		conn.id = strings.clone_from(sqlite.column_text(stmt, 0))
		conn.name = strings.clone_from(sqlite.column_text(stmt, 1))
		conn.db_type = strings.clone_from(sqlite.column_text(stmt, 2))

		if SQLite_Datatypes(sqlite.column_type(stmt, 3)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 3))
			conn.host = new_clone(s)
		}

		if SQLite_Datatypes(sqlite.column_type(stmt, 4)) != .NULL {
			v := int(sqlite.column_int(stmt, 4))
			conn.port = new_clone(v)
		}

		if SQLite_Datatypes(sqlite.column_type(stmt, 5)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 5))
			conn.database_name = new_clone(s)
		}

		if SQLite_Datatypes(sqlite.column_type(stmt, 6)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 6))
			conn.username = new_clone(s)
		}

		conn.sql_enabled = int(sqlite.column_int(stmt, 7))
		if SQLite_Datatypes(sqlite.column_type(stmt, 8)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 8))
			conn.credential_id = new_clone(s)
		}

		if SQLite_Datatypes(sqlite.column_type(stmt, 9)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 9))
			conn.color = new_clone(s)
		}

		if SQLite_Datatypes(sqlite.column_type(stmt, 10)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 10))
			conn.icon = new_clone(s)
		}

		conn.is_favorite = int(sqlite.column_int(stmt, 11))
		conn.created_at = strings.clone_from(sqlite.column_text(stmt, 12))
		conn.updated_at = strings.clone_from(sqlite.column_text(stmt, 13))
		if SQLite_Datatypes(sqlite.column_type(stmt, 14)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 14))
			conn.last_connected_at = new_clone(s)
		}

		append(&connections, conn)
	}

	return connections[:]
}

New_Credential :: struct {
	auth_type:  string,
	secret_key: string,
}

Credential :: struct {
	id:         string,
	auth_type:  string,
	secret_key: string,
}

create_credential :: proc(db: ^sqlite.Connection, creds: ^New_Credential) -> Credential {
	creds_sql: cstring = `
		INSERT INTO credentials (
			id, auth_type, secret_key
		) VALUES (?, ?, ?)`

	stmt: ^sqlite.Statement
	if sqlite.prepare_v2(db, creds_sql, -1, &stmt, nil) != .Ok {
		panic("prepare_v2 failed")
	}
	defer sqlite.finalize(stmt)

	sqlite_destructor := sqlite.Destructor {
		behaviour = .Static,
	}

	id_cstr := strings.clone_to_cstring(create_id())
	defer delete(id_cstr)
	sqlite.bind_text(stmt, 1, id_cstr, -1, sqlite_destructor)

	auth_type_cstr := strings.clone_to_cstring(creds.auth_type)
	defer delete(auth_type_cstr)
	sqlite.bind_text(stmt, 2, auth_type_cstr, -1, sqlite_destructor)

	secret_key_cstr := strings.clone_to_cstring(creds.secret_key)
	defer delete(secret_key_cstr)
	sqlite.bind_text(stmt, 3, secret_key_cstr, -1, sqlite_destructor)

	if sqlite.step(stmt) != .Done {
		panic("step failed")
	}

	cred := Credential {
		id         = strings.clone_from(id_cstr),
		auth_type  = strings.clone_from(auth_type_cstr),
		secret_key = strings.clone_from(secret_key_cstr),
	}

	return cred
}

New_Connection :: struct {
	name:          string,
	db_type:       string,
	host:          string,
	port:          int,
	database_name: string,
	username:      string,
	ssl_enabled:   bool,
	credential_id: string,
	color:         ^string,
	icon:          ^string,
	is_favorite:   bool,
}


create_connection :: proc(db: ^sqlite.Connection, new_conn: ^New_Connection) {
	conn_sql: cstring = `
		INSERT INTO connections (
			id,
			name,
			db_type,
			host,
			port,
			database_name,
			username,
			ssl_enabled,
			credential_id,
			color,
			icon,
			is_favorite
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`

	stmt: ^sqlite.Statement
	if sqlite.prepare_v2(db, conn_sql, -1, &stmt, nil) != .Ok {
		panic("prepare_v2 failed")
	}
	defer sqlite.finalize(stmt)

	sqlite_destructor := sqlite.Destructor {
		behaviour = .Static,
	}

	id_cstr := strings.clone_to_cstring(create_id())
	defer delete(id_cstr)
	sqlite.bind_text(stmt, 1, id_cstr, -1, sqlite_destructor)

	name_cstr := strings.clone_to_cstring(new_conn.name)
	defer delete(name_cstr)
	sqlite.bind_text(stmt, 2, name_cstr, -1, sqlite_destructor)

	db_type_cstr := strings.clone_to_cstring(new_conn.db_type)
	defer delete(db_type_cstr)
	sqlite.bind_text(stmt, 3, db_type_cstr, -1, sqlite_destructor)

	cstr := strings.clone_to_cstring(new_conn.host)
	defer delete(cstr)
	sqlite.bind_text(stmt, 4, cstr, -1, sqlite_destructor)

	sqlite.bind_int(stmt, 5, c.int(new_conn.port))

	db_name_cstr := strings.clone_to_cstring(new_conn.database_name)
	defer delete(db_name_cstr)
	sqlite.bind_text(stmt, 6, db_name_cstr, -1, sqlite_destructor)

	username_cstr := strings.clone_to_cstring(new_conn.username)
	defer delete(username_cstr)
	sqlite.bind_text(stmt, 7, username_cstr, -1, sqlite_destructor)

	sqlite.bind_int(stmt, 8, c.int(0 if !new_conn.ssl_enabled else 1))

	credential_id_cstr := strings.clone_to_cstring(new_conn.credential_id)
	defer delete(credential_id_cstr)
	sqlite.bind_text(stmt, 9, credential_id_cstr, -1, sqlite_destructor)

	if new_conn.color != nil {
		color_cstr := strings.clone_to_cstring(new_conn.color^)
		defer delete(color_cstr)
		sqlite.bind_text(stmt, 10, color_cstr, -1, sqlite_destructor)
	} else {
		sqlite.bind_null(stmt, 10)
	}

	if new_conn.icon != nil {
		icon_cstr := strings.clone_to_cstring(new_conn.icon^)
		defer delete(icon_cstr)
		sqlite.bind_text(stmt, 11, icon_cstr, -1, sqlite_destructor)
	} else {
		sqlite.bind_null(stmt, 11)
	}

	sqlite.bind_int(stmt, 12, c.int(0 if !new_conn.is_favorite else 1))
	if sqlite.step(stmt) != .Done {
		panic("step failed")
	}
}

Db_New_Connection :: struct {
	credential: ^New_Credential,
	conn:       ^New_Connection,
}

save_db_connection :: proc(db: ^sqlite.Connection, new_conn: ^Db_New_Connection) {
	new_cred := New_Credential {
		auth_type  = new_conn.credential.auth_type,
		secret_key = new_conn.credential.secret_key,
	}

	cred := create_credential(db, &new_cred)

	conn := New_Connection {
		name          = new_conn.conn.name,
		db_type       = new_conn.conn.db_type,
		host          = new_conn.conn.host,
		port          = new_conn.conn.port,
		database_name = new_conn.conn.database_name,
		username      = new_conn.conn.username,
		ssl_enabled   = new_conn.conn.ssl_enabled,
		credential_id = cred.id,
		color         = new_conn.conn.color,
		icon          = new_conn.conn.icon,
		is_favorite   = new_conn.conn.is_favorite,
	}

	create_connection(db, &conn)
}

create_id :: proc() -> string {
	return uuid.to_string(uuid.generate_v7())
}
