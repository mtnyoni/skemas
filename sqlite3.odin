package main

import "core:c"
import "core:strings"
import sqlite3 "vendor/odin-sqlite3"

sqlite_connect :: proc(params: Db_New_Connection) -> (^sqlite3.Connection, DB_Error) {
	db: ^sqlite3.Connection = nil
	path := strings.clone_to_cstring(params.conn.host, context.temp_allocator)
	if rc := sqlite3.open(path, &db); rc != .Ok {
		return nil, DB_OpenFailed{message = strings.clone_from_cstring(sqlite3.errmsg(db))}
	}
	return db, nil
}

sqlite_get_tables :: proc(db: ^sqlite3.Connection) -> []string {
	sql: cstring = `
		SELECT name
		FROM sqlite_master
		WHERE type = 'table'
		AND name NOT LIKE 'sqlite_%'
		ORDER BY name;
	`

	stmt: ^sqlite3.Statement = nil
	if rc := sqlite3.prepare_v2(db, sql, -1, &stmt, nil); rc != .Ok {
		return nil
	}
	defer sqlite3.finalize(stmt)

	tables: [dynamic]string
	for sqlite3.step(stmt) == .Row {
		append(&tables, strings.clone_from_cstring(sqlite3.column_text(stmt, 0)))
	}
	return tables[:]
}

sqlite_run_query :: proc(conn: ^sqlite3.Connection, query: string) -> (QueryResult, DB_Error) {
	stmt: ^sqlite3.Statement = nil
	sql := strings.clone_to_cstring(query, context.temp_allocator)

	if rc := sqlite3.prepare_v2(conn, sql, -1, &stmt, nil); rc != .Ok {
		return {}, DB_ExecFailed{message = strings.clone_from_cstring(sqlite3.errmsg(conn))}
	}
	defer sqlite3.finalize(stmt)

	n_cols := int(sqlite3.column_count(stmt))
	if n_cols == 0 {
		if rc := sqlite3.step(stmt); rc != .Done && rc != .Ok {
			return {}, DB_ExecFailed{message = strings.clone_from_cstring(sqlite3.errmsg(conn))}
		}

		return QueryResult{command_tag = "OK"}, nil
	}

	headers := make([]string, n_cols)
	for col in 0 ..< n_cols {
		headers[col] = strings.clone_from_cstring(sqlite3.column_name(stmt, c.int(col)))
	}

	rows: [dynamic][]string
	for {
		rc := sqlite3.step(stmt)
		if rc == .Done do break
		if rc != .Row {
			return {}, DB_ExecFailed{message = strings.clone_from_cstring(sqlite3.errmsg(conn))}
		}

		cells := make([]string, n_cols)
		for col in 0 ..< n_cols {
			if sqlite3.column_type(stmt, c.int(col)) == SQLITE_NULL {
				cells[col] = "NULL"
			} else {
				cells[col] = strings.clone_from_cstring(sqlite3.column_text(stmt, c.int(col)))
			}
		}

		append(&rows, cells)
	}

	return QueryResult{headers = headers, rows = rows[:]}, nil
}
