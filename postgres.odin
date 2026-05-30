package main

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
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
		return nil, DB_OpenFailed{message = "connectdb returned nil"}
	}

	if pq.status(pg_conn) != .Ok {
		return nil, DB_OpenFailed{message = strings.clone_from_cstring(pq.error_message(pg_conn))}
	}

	return new_clone(pg_conn), nil
}

pg_get_dbs :: proc(conn: ^pq.Conn) -> ([]string, DB_Error) {
	if pq.status(conn^) != .Ok {
		return nil, DB_OpenFailed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}

	res := pq.exec(conn^, "SELECT datname FROM pg_database ORDER BY datname;")
	defer pq.clear(res)

	if pq.result_status(res) != .Tuples_OK {
		return nil, DB_OpenFailed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}

	count := pq.n_tuples(res)
	dbs := make([]string, count)
	for i in 0 ..< count {
		dbs[i] = strings.clone_from_cstring(cstring(pq.get_value(res, i, 0)))
	}

	return dbs, nil
}

Conn_Health_Checker :: struct {
	mu:         sync.Mutex,
	status:     ConnectionStatus,
	latency_ms: f32,
	active:     bool,
}

_Health_Check_Args :: struct {
	checker:     ^Conn_Health_Checker,
	conn_string: string,
}

_health_check_worker :: proc(t: ^thread.Thread) {
	args := cast(^_Health_Check_Args)t.data
	checker := args.checker
	conn_string := args.conn_string
	free(args)

	buf: [1024]byte
	n := copy(buf[:len(buf) - 1], conn_string)
	buf[n] = 0
	delete(conn_string)

	tmp := pq.connectdb(cstring(&buf[0]))
	defer if tmp != nil {pq.finish(tmp)}

	status: ConnectionStatus = .Disconnected
	latency_ms: f32
	if tmp != nil && pq.status(tmp) == .Ok {
		status = .Connected
		t := time.tick_now()
		res := pq.exec(tmp, "SELECT 1")
		latency_ms = f32(time.duration_microseconds(time.tick_since(t))) / 1000.0
		pq.clear(res)
	}

	sync.lock(&checker.mu)
	checker.status = status
	checker.latency_ms = latency_ms
	checker.active = false
	sync.unlock(&checker.mu)
}

pg_spawn_health_check :: proc(checker: ^Conn_Health_Checker, pg_conn: PQ_Conn) -> ^thread.Thread {
	sync.lock(&checker.mu)
	if checker.active {
		sync.unlock(&checker.mu)
		return nil
	}
	checker.active = true
	sync.unlock(&checker.mu)

	h := pq.host(pg_conn^)
	p := pq.port(pg_conn^)
	u := pq.user(pg_conn^)
	pw := pq.pass(pg_conn^)
	if pw == nil {pw = ""}
	db := pq.db(pg_conn^)
	ssl: cstring = "require" if pq.ssl_in_use(pg_conn^) else "disable"

	args := new(_Health_Check_Args)
	args.checker = checker
	args.conn_string = strings.clone(
		fmt.tprintf(
			"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
			h,
			p,
			u,
			pw,
			db,
			ssl,
		),
	)

	t := thread.create(_health_check_worker)
	t.data = args
	thread.start(t)
	return t
}

pg_conn_status :: proc(checker: ^Conn_Health_Checker) -> ConnectionStatus {
	sync.lock(&checker.mu)
	defer sync.unlock(&checker.mu)
	return checker.status
}

pg_conn_latency :: proc(checker: ^Conn_Health_Checker) -> f32 {
	sync.lock(&checker.mu)
	defer sync.unlock(&checker.mu)
	return checker.latency_ms
}

pg_server_version_major :: proc(conn: ^pq.Conn) -> i32 {
	return pq.server_version(conn^) / 10000
}

pg_client_encoding :: proc(conn: ^pq.Conn) -> string {
	res := pq.exec(conn^, "SHOW client_encoding")
	defer pq.clear(res)
	if pq.result_status(res) == .Tuples_OK && pq.n_tuples(res) > 0 {
		return strings.clone_from_cstring(cstring(pq.get_value(res, 0, 0)))
	}
	return "UTF8"
}

pg_is_read_only :: proc(conn: ^pq.Conn) -> bool {
	res := pq.exec(conn^, "SHOW default_transaction_read_only")
	defer pq.clear(res)
	if pq.result_status(res) == .Tuples_OK && pq.n_tuples(res) > 0 {
		return strings.clone_from_cstring(cstring(pq.get_value(res, 0, 0))) == "on"
	}
	return false
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
		return nil, DB_OpenFailed{message = "connectdb returned nil"}
	}
	if pq.status(new_conn) != .Ok {
		msg := strings.clone_from_cstring(pq.error_message(new_conn))
		pq.finish(new_conn)
		return nil, DB_OpenFailed{message = msg}
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
		return nil, DB_OpenFailed{message = strings.clone_from_cstring(pq.error_message(conn^))}
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
		return nil, DB_ExecFailed{message = strings.clone_from_cstring(pq.error_message(conn^))}
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
		return {}, DB_ExecFailed{message = strings.clone_from_cstring(pq.error_message(conn^))}
	}
}
