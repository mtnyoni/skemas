package main

import "core:c"
import "core:encoding/uuid"
import "core:strings"
import sqlite "vendor/odin-sqlite3"

DB_Error :: union {
	DB_Open_Failed,
	DB_Exec_Failed,
	DB_Prepare_Failed,
	DB_Step_Failed,
}

DB_Open_Failed :: struct {
	message: string,
}

DB_Exec_Failed :: struct {
	message: string,
}

DB_Prepare_Failed :: struct {
	message: string,
}

DB_Step_Failed :: struct {
	message: string,
}


connect :: proc() -> (^sqlite.Connection, DB_Error) {
	db: ^sqlite.Connection = nil
	if rc := sqlite.open("./db.sqlite", &db); rc != .Ok {
		return nil, DB_Open_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}
	return db, nil
}

create_tables :: proc(db: ^sqlite.Connection) -> DB_Error {
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
		return DB_Exec_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}

	connection_table_sql: cstring = `
		CREATE TABLE IF NOT EXISTS connections (
		    id TEXT PRIMARY KEY,
		    name TEXT NOT NULL UNIQUE,
		    db_type TEXT NOT NULL
		        CHECK(db_type IN (
		            'postgres',
		            'sqlite'
		        )),

		    host TEXT NOT NULL,
		    port INTEGER NOT NULL,
		    username TEXT NOT NULL,

		    ssl_enabled INTEGER NOT NULL DEFAULT 0,
		    credential_id TEXT NOT NULL,
		    color TEXT,
		    icon TEXT,
		    is_favorite INTEGER DEFAULT 0,

		    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
		    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
		    last_connected_at TEXT DEFAULT CURRENT_TIMESTAMP,

		    FOREIGN KEY (credential_id) REFERENCES credentials(id)
		);`

	if sqlite.exec(db, connection_table_sql, nil, nil, nil) != .Ok {
		return DB_Exec_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
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
		return DB_Exec_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
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
		return DB_Exec_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}

	return nil
}

Database_Type :: enum {
	Postgres,
	SQLite,
}

Connection :: struct {
	id:                string,
	name:              string,
	db_type:           Database_Type,
	host:              string,
	port:              int,
	username:          string,
	sql_enabled:       bool,
	credential_id:     string,
	color:             ^string,
	icon:              ^string,
	is_favorite:       bool,
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

get_connections :: proc(db: ^sqlite.Connection) -> ([]Connection, DB_Error) {
	sql: cstring = `
		SELECT
			id,
			name,
			db_type,
			host,
			port,
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
		return nil, DB_Prepare_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}
	defer sqlite.finalize(stmt)

	connections: [dynamic]Connection

	for sqlite.step(stmt) == .Row {
		conn := Connection{}
		conn.id = strings.clone_from(sqlite.column_text(stmt, 0))
		conn.name = strings.clone_from(sqlite.column_text(stmt, 1))

		db_type := strings.clone_from(sqlite.column_text(stmt, 2))
		switch db_type {
		case "postgres":
			conn.db_type = Database_Type.Postgres

		case "sqlite":
			conn.db_type = Database_Type.SQLite
		}

		conn.host = strings.clone_from(sqlite.column_text(stmt, 3))
		conn.port = int(sqlite.column_int(stmt, 4))
		conn.username = strings.clone_from(sqlite.column_text(stmt, 5))

		conn.sql_enabled = true if int(sqlite.column_int(stmt, 6)) == 1 else false
		conn.credential_id = strings.clone_from(sqlite.column_text(stmt, 7))

		if SQLite_Datatypes(sqlite.column_type(stmt, 8)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 8))
			conn.color = new_clone(s)
		}

		if SQLite_Datatypes(sqlite.column_type(stmt, 9)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 9))
			conn.icon = new_clone(s)
		}

		conn.is_favorite = true if int(sqlite.column_int(stmt, 10)) == 1 else false
		conn.created_at = strings.clone_from(sqlite.column_text(stmt, 11))
		conn.updated_at = strings.clone_from(sqlite.column_text(stmt, 12))
		if SQLite_Datatypes(sqlite.column_type(stmt, 13)) != .NULL {
			s := strings.clone_from(sqlite.column_text(stmt, 13))
			conn.last_connected_at = new_clone(s)
		}

		append(&connections, conn)
	}

	return connections[:], nil
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

create_credential :: proc(
	db: ^sqlite.Connection,
	creds: ^New_Credential,
) -> (
	^Credential,
	DB_Error,
) {
	creds_sql: cstring = `
		INSERT INTO credentials (
			id, auth_type, secret_key
		) VALUES (?, ?, ?)`

	stmt: ^sqlite.Statement
	if sqlite.prepare_v2(db, creds_sql, -1, &stmt, nil) != .Ok {
		return nil, DB_Prepare_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
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
		return nil, DB_Step_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}

	cred := Credential {
		id         = strings.clone_from(id_cstr),
		auth_type  = strings.clone_from(auth_type_cstr),
		secret_key = strings.clone_from(secret_key_cstr),
	}

	return new_clone(cred), nil
}

New_Connection :: struct {
	name:          string,
	db_type:       Database_Type,
	host:          string,
	port:          int,
	username:      string,
	ssl_enabled:   bool,
	credential_id: string,
	color:         ^string,
	icon:          ^string,
	is_favorite:   bool,
}


create_connection :: proc(db: ^sqlite.Connection, new_conn: ^New_Connection) -> DB_Error {
	conn_sql: cstring = `
		INSERT INTO connections (
			id,
			name,
			db_type,
			host,
			port,
			username,
			ssl_enabled,
			credential_id,
			color,
			icon,
			is_favorite
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`

	stmt: ^sqlite.Statement
	if sqlite.prepare_v2(db, conn_sql, -1, &stmt, nil) != .Ok {
		return DB_Prepare_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
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

	db_type_str: string
	switch new_conn.db_type {
	case .Postgres:
		db_type_str = "postgres"
	case .SQLite:
		db_type_str = "sqlite"
	}
	db_type_cstr := strings.clone_to_cstring(db_type_str)
	defer delete(db_type_cstr)
	sqlite.bind_text(stmt, 3, db_type_cstr, -1, sqlite_destructor)

	cstr := strings.clone_to_cstring(new_conn.host)
	defer delete(cstr)
	sqlite.bind_text(stmt, 4, cstr, -1, sqlite_destructor)

	sqlite.bind_int(stmt, 5, c.int(new_conn.port))

	username_cstr := strings.clone_to_cstring(new_conn.username)
	defer delete(username_cstr)
	sqlite.bind_text(stmt, 6, username_cstr, -1, sqlite_destructor)

	sqlite.bind_int(stmt, 7, c.int(0 if !new_conn.ssl_enabled else 1))

	credential_id_cstr := strings.clone_to_cstring(new_conn.credential_id)
	defer delete(credential_id_cstr)
	sqlite.bind_text(stmt, 8, credential_id_cstr, -1, sqlite_destructor)

	if new_conn.color != nil {
		color_cstr := strings.clone_to_cstring(new_conn.color^)
		defer delete(color_cstr)
		sqlite.bind_text(stmt, 9, color_cstr, -1, sqlite_destructor)
	} else {
		sqlite.bind_null(stmt, 9)
	}

	if new_conn.icon != nil {
		icon_cstr := strings.clone_to_cstring(new_conn.icon^)
		defer delete(icon_cstr)
		sqlite.bind_text(stmt, 10, icon_cstr, -1, sqlite_destructor)
	} else {
		sqlite.bind_null(stmt, 10)
	}

	sqlite.bind_int(stmt, 11, c.int(0 if !new_conn.is_favorite else 1))
	if sqlite.step(stmt) != .Done {
		return DB_Step_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}

	return nil
}

Db_New_Connection :: struct {
	creds: ^New_Credential,
	conn:  ^New_Connection,
}

save_db_connection :: proc(db: ^sqlite.Connection, new_conn: ^Db_New_Connection) -> DB_Error {
	if sqlite.exec(db, "BEGIN", nil, nil, nil) != .Ok {
		return DB_Step_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}

	new_cred := New_Credential {
		auth_type  = new_conn.creds.auth_type,
		secret_key = new_conn.creds.secret_key,
	}

	cred, err := create_credential(db, &new_cred)
	if err != nil {
		sqlite.exec(db, "ROLLBACK", nil, nil, nil)
		return err
	}

	conn := New_Connection {
		name          = new_conn.conn.name,
		db_type       = new_conn.conn.db_type,
		host          = new_conn.conn.host,
		port          = new_conn.conn.port,
		username      = new_conn.conn.username,
		ssl_enabled   = new_conn.conn.ssl_enabled,
		credential_id = cred.id,
		color         = new_conn.conn.color,
		icon          = new_conn.conn.icon,
		is_favorite   = new_conn.conn.is_favorite,
	}

	err = create_connection(db, &conn)
	if err != nil {
		sqlite.exec(db, "ROLLBACK", nil, nil, nil)
		return err
	}

	if sqlite.exec(db, "COMMIT", nil, nil, nil) != .Ok {
		sqlite.exec(db, "ROLLBACK", nil, nil, nil)
		return DB_Step_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}

	return nil
}


get_credential :: proc(db: ^sqlite.Connection, id: string) -> (Credential, DB_Error) {
	sql: cstring = `SELECT id, auth_type, secret_key FROM credentials WHERE id = ?`

	stmt: ^sqlite.Statement
	if sqlite.prepare_v2(db, sql, -1, &stmt, nil) != .Ok {
		return {}, DB_Prepare_Failed{message = strings.clone_from_cstring(sqlite.errmsg(db))}
	}
	defer sqlite.finalize(stmt)

	id_cstr := strings.clone_to_cstring(id)
	defer delete(id_cstr)
	sqlite_destructor := sqlite.Destructor {
		behaviour = .Static,
	}
	sqlite.bind_text(stmt, 1, id_cstr, -1, sqlite_destructor)

	if sqlite.step(stmt) != .Row {
		return {}, DB_Step_Failed{message = "credential not found"}
	}

	return Credential {
			id = strings.clone_from(sqlite.column_text(stmt, 0)),
			auth_type = strings.clone_from(sqlite.column_text(stmt, 1)),
			secret_key = strings.clone_from(sqlite.column_text(stmt, 2)),
		},
		nil
}

create_id :: proc() -> string {
	return uuid.to_string(uuid.generate_v7())
}
