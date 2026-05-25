package main

import "core:fmt"
import "core:strings"
import pq "vendor/odin-postgresql"

make_conn_string :: proc(conn: Db_New_Connection) -> cstring {
	conn_string := fmt.tprintf(
		"host=%s port=%d user=%s password=%s sslmode=%s",
		conn.conn.host,
		conn.conn.port,
		conn.conn.username,
		conn.creds.secret_key,
		"require" if conn.conn.ssl_enabled else "disable",
	)

	return strings.clone_to_cstring(conn_string, context.temp_allocator)
}

pg_connect :: proc(params: Db_New_Connection) -> (^pq.Conn, DB_Error) {
	pg_conn := pq.connectdb(make_conn_string(params))
	if pg_conn == nil {
		return nil, DB_Open_Failed{message = "connectdb returned nil"}
	}

	if pq.status(pg_conn) != .Ok {
		return nil, DB_Open_Failed{message = strings.clone_from_cstring(pq.error_message(pg_conn))}
	}

	return new_clone(pg_conn), nil
}

pg_get_dbs :: proc(conn: ^pq.Conn) -> ([]string, DB_Error) {
	if pq.status(conn^) != .Ok {
		return nil, DB_Open_Failed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}

	res := pq.exec(conn^, "SELECT datname FROM pg_database ORDER BY datname;")
	defer pq.clear(res)

	if pq.result_status(res) != .Tuples_OK {
		return nil, DB_Open_Failed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}

	count := pq.n_tuples(res)
	dbs := make([]string, count)
	for i in 0 ..< count {
		dbs[i] = strings.clone_from_cstring(cstring(pq.get_value(res, i, 0)))
	}

	return dbs, nil
}

pg_current_db :: proc(conn: ^pq.Conn) -> string {
	return strings.clone_from_cstring(pq.db(conn^))
}

pg_connect_to_db :: proc(conn: ^pq.Conn, dbname: string) -> (^pq.Conn, DB_Error) {
	h := pq.host(conn^)
	p := pq.port(conn^)
	u := pq.user(conn^)
	pw := pq.pass(conn^)
	if pw == nil {pw = ""}

	sslmode: cstring = "require" if pq.ssl_in_use(conn^) else "disable"

	conn_string := fmt.tprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		h,
		p,
		u,
		pw,
		dbname,
		sslmode,
	)

	new_conn := pq.connectdb(strings.clone_to_cstring(conn_string, context.temp_allocator))
	if new_conn == nil {
		return nil, DB_Open_Failed{message = "connectdb returned nil"}
	}
	if pq.status(new_conn) != .Ok {
		msg := strings.clone_from_cstring(pq.error_message(new_conn))
		pq.finish(new_conn)
		return nil, DB_Open_Failed{message = msg}
	}

	return new_clone(new_conn), nil
}

pg_get_schemas :: proc(conn: ^pq.Conn) -> ([]string, DB_Error) {
	sql: cstring = `
		SELECT schema_name
		FROM information_schema.schemata
		WHERE schema_name NOT LIKE 'pg_%' AND schema_name != 'information_schema'
		ORDER BY schema_name;
	`

	res := pq.exec(conn^, sql)
	defer pq.clear(res)

	if pq.result_status(res) != .Tuples_OK {
		return nil, DB_Open_Failed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}

	count := pq.n_tuples(res)
	result := make([]string, count)
	for i in 0 ..< count {
		result[i] = strings.clone_from_cstring(cstring(pq.get_value(res, i, 0)))
	}

	return result, nil
}

pg_get_tables :: proc(conn: ^pq.Conn, schema: string) -> ([]string, DB_Error) {
	sql: cstring = `
		SELECT table_name
		FROM information_schema.tables
		WHERE table_schema = $1 AND table_type = 'BASE TABLE'
		ORDER BY table_name;
	`

	schema_cstr := strings.clone_to_cstring(schema, context.temp_allocator)
	schema_val := cast([^]byte)schema_cstr

	res := pq.exec_params(conn^, sql, 1, nil, &schema_val, nil, nil, .Text)
	defer pq.clear(res)

	if pq.result_status(res) != .Tuples_OK {
		return nil, DB_Exec_Failed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}

	count := pq.n_tuples(res)
	result := make([]string, count)
	for i in 0 ..< count {
		result[i] = strings.clone_from_cstring(cstring(pq.get_value(res, i, 0)))
	}

	return result, nil
}

QueryResult :: struct {
	headers:     []string,
	rows:        [][]string,
	command_tag: string,
}

pg_run_query :: proc(conn: ^pq.Conn, query: string) -> (QueryResult, DB_Error) {
	res := pq.exec(conn^, strings.clone_to_cstring(query, context.temp_allocator))
	defer pq.clear(res)

	#partial switch pq.result_status(res) {
	case .Tuples_OK:
		n_cols := pq.n_fields(res)
		n_rows := pq.n_tuples(res)

		headers := make([]string, n_cols)
		for col in 0 ..< n_cols {
			headers[col] = strings.clone_from_cstring(pq.f_name(res, col))
		}

		rows := make([][]string, n_rows)
		for row in 0 ..< n_rows {
			cells := make([]string, n_cols)
			for col in 0 ..< n_cols {
				if bool(pq.get_is_null(res, row, col)) {
					cells[col] = "NULL"

				} else {
					cells[col] = strings.clone_from_cstring(cstring(pq.get_value(res, row, col)))
				}
			}
			rows[row] = cells
		}

		return QueryResult{headers = headers, rows = rows}, nil

	case .Command_OK:
		tag := strings.clone_from_cstring(pq.cmd_status(res))
		return QueryResult{command_tag = tag}, nil

	case:
		return {}, DB_Exec_Failed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}
}
