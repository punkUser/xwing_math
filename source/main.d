import www_server;
import std.stdio;

import vibe.vibe;

void start_servers(string[] args)
{
    try
    {
        WWWServerSettings settings;

        WWWServer www_server = new WWWServer(settings);
        runEventLoop();
    }
    catch (Exception e)
    {
        writeln(e.msg);
    }
}

int main(string[] args)
{
    // Get useful stack dumps on linux
    {
        import etc.linux.memoryerror;
        static if (is(typeof(registerMemoryErrorHandler)))
            registerMemoryErrorHandler();
    }

    //vibe.core.log.setLogFile("vibe_log.txt", LogLevel.Trace);
    //setLogLevel(LogLevel.debugV);

    start_servers(args);

    return 0;
}
