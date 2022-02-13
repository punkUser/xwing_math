import www_server;
import benchmark;

import std.stdio;
import std.getopt;

import vibe.vibe;

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

    // Command line options
    bool benchmark = false;
    auto helpInformation = getopt(args,
                                  "benchmark", &benchmark);

    try
    {
        if (benchmark)
        {
            run_benchmarks();
        }
        else
        {
            WWWServerSettings settings;
            WWWServer www_server = new WWWServer(settings);
            runEventLoop();
        }
    }
    catch (Exception e)
    {
        writeln(e.msg);
    }

    return 0;
}
