import simulation2;
import simulation_state2;
import simulation_setup2;
import simulation_results;
import attack_form;
import defense_form;
import form;
import regression_tests;

import std.stdio;
import std.array;
import std.algorithm;
import std.conv;
import std.math;
import std.datetime;
import std.datetime.stopwatch : StopWatch, AutoStart;

private struct Benchmark
{
    string name;
    string form_string;
};

private static immutable Benchmark[] k_benchmarks = [
    { "SlowSingleAttack",       "d=gwAAAAcAAAAA&a1=UQgAIEUZAv4T" },
];

public void run_benchmarks()
{
    foreach (ref test; k_benchmarks)
    {
        auto sw = StopWatch(AutoStart.yes);
        auto results = run_test(test.form_string);
        writefln("%s: %sms", test.name, sw.peek().total!"msecs");
    }
}
