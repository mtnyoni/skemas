package main

import "core:fmt"
import "core:strings"
import "core:time"
import im "vendor/odin-imgui"

Toast_Type :: enum {
	Info,
	Success,
	Warning,
	Error,
}

Toast :: struct {
	message:    string,
	type_:      Toast_Type,
	spawn_time: time.Tick,
	duration:   f32,
}

active_toasts: [dynamic]Toast

push_toast :: proc(message: string, type_: Toast_Type, duration: f32 = 3.0) {
	append(
		&active_toasts,
		Toast{message = message, type_ = type_, spawn_time = time.tick_now(), duration = duration},
	)
}


draw_toasts :: proc() {
	if len(active_toasts) == 0 do return

	viewport := im.GetMainViewport()
	PAD := f32(20.0)

	next_y_offset := viewport.WorkPos.y + viewport.WorkSize.y - PAD

	flags := im.WindowFlags{
		.NoTitleBar,
		.NoResize,
		.NoMove,
		.NoScrollbar,
		.NoSavedSettings,
		.NoMouseInputs,
		.NoNavInputs,
		.NoNavFocus,
		.AlwaysAutoResize,
	}

	// Iterate backwards to safely remove expired elements
	for i := len(active_toasts) - 1; i >= 0; i -= 1 {
		toast := active_toasts[i]

		// Calculate age
		elapsed := time.tick_since(toast.spawn_time)
		elapsed_seconds := f32(time.duration_seconds(elapsed))

		// Remove toast if expired
		if elapsed_seconds >= toast.duration {
			unordered_remove(&active_toasts, i)
			continue
		}

		// Set color style based on type
		bg_color := im.Vec4{0.1, 0.1, 0.1, 0.85} // default info dark gray
		switch toast.type_ {
		case .Success:
			bg_color = im.Vec4{0.1, 0.4, 0.1, 0.9}
		case .Warning:
			bg_color = im.Vec4{0.4, 0.3, 0.0, 0.9}
		case .Error:
			bg_color = im.Vec4{0.5, 0.1, 0.1, 0.9}
		case .Info: // uses default
		}

		im.PushStyleColorImVec4(.WindowBg, bg_color)

		// Dynamically calculate individual toast window position
		// We temporarily create a window layout to grab its height
		im.SetNextWindowPos(
			{viewport.WorkPos.x + viewport.WorkSize.x - PAD, next_y_offset},
			.Always,
			{1.0, 1.0},
		)

		// Render unique overlay instance per active toast
		window_id := strings.clone_to_cstring(fmt.tprintf("##toast_%d", i))
		defer delete(window_id)

		if im.Begin(window_id, nil, flags) {
			c_msg := strings.clone_to_cstring(toast.message)
			defer delete(c_msg)
			im.TextUnformatted(c_msg)

			// Adjust offset for the next toast stacked above it
			next_y_offset -= im.GetWindowHeight() + 8.0
		}
		im.End()
		im.PopStyleColor()
	}
}
