module log;

import std.stdio;
import std.file;
import std.datetime;
import std.string;

import vibe.data.json;

// Very simple file logging - can expand when needed

// TODO: Fix for multiple threads/shared
private	static File s_log;

public static this()
{
	s_log = stdout;
}

public void initialize_logging(string file_name)
{
	s_log = File(file_name, "a");
}

private string get_time_string()
{
	auto dt = Clock.currTime();
	return format("%04d-%02d-%02d %02d:%02d:%02d",
				  dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
}

public void log_message(A...)(in char[] format, A args)
{
	s_log.writefln("%s: " ~ format, get_time_string(), args);
	s_log.flush();
}
