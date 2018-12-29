import simulation2;
import simulation_state2;
import simulation_setup2;
import simulation_results;
import attack_form;
import defense_form;
import form;

import std.stdio;
import std.array;
import std.algorithm;
import std.conv;
import std.math;
import std.datetime;
import std.datetime.stopwatch : StopWatch, AutoStart;

private struct Test
{
    string name;
    string form_string;
    double expected_damage;
};

private immutable double k_expected_damage_epsilon = 5e-16;

// Test name abbreviations:
//   f = focus, l = lock, c = calculate, o = force, e = evade
private static immutable Test[] k_regression_test_cases = [
    { "3f vs 3f",               "d=gwAAAAAAAAA&a1=MQgAAAAAAAA",                     0.637756347656250 },
    { "3lo+LW vs 0",            "d=gAAAAAAAAAA&a1=MwEAAAAIAAA",                     2.695068359375000 }, // Tests attacker forward search
    { "3fl vs 3fe+LW",          "d=gyAABAAAAAA&a1=MwgAAAAAAAA",                     0.144477188587189 },
    { "2x 3fl vs 3fe+re",       "d=gyABAAAAAAA&a1=MwgAAAAAAAA&a2=MwgAAAAAAAA",      0.937748962769547 },
    { "2x 3fl vs 3fe",          "d=gyAAAAAAAAA&a1=MwgAAAAAAAA&a2=MwgAAAAAAAA",      1.429703696999240 },
    { "3 vs 0 biggs",           "d=AAAAEAAAAAA&a1=MQAAAAAAAAA",                     0.625             },
    { "3l fearless vs 0",       "d=AAAAAAAAAAA&a1=MwAAAAAAAgA",                     2.828125000000000 },
    { "4 all hits",             "d=AAAAAAAAAAA&a1=QQAAAAACAAA",                     4.0               },
    { "0+shara fl",             "d=AAAAAAAAAAA&a1=AwgAAAIAAAA",                     1.0               }, // Shara add result even without dice
    { "3fl vs 1fl+shara",       "d=gQAAAAQBAAA&a1=MwgAAAAAAAA",                     1.194763183593750 },
    { "6x 2f+howl vs 3fe+Iden", "d=gyAAQAAAAAA&a1=IQgAAAAEAAA&a2=IQgAAAAEAAA&a3=IQgAAAAEAAA&a4=IQgAAAAEAAA&a5=IQgAAAAEAAA&a6=IQgAAAAEAAA",
                                                                                    1.740283006218120 },
    { "4 vs 0+L337",            "d=AAAAAEAAAAA&a1=QQAAAAAAAAA",                     1.625             },
    { "3l vs 0+L337",           "d=AAAAAEAAAAA&a1=MwAAAAAAAAA",                     1.5               }, // Always use L3-37 except on all blanks (better than attacker rerolling just blanks/focus)
    { "3f vs 2o+ezra",          "d=EgAIAAwAAAA&a1=MQgAAAAAAAA",                     1.074462890625000 },
    { "3fl vs 2e+rebel_falcon", "d=AiAAAAAACAA&a1=MwgAAAAAAAA",                     1.065373420715332 },
    { "3l+finn vs 0",           "d=AAAAAAAAAAA&a1=MwAAAAAAAAg",                     2.75              },
    { "3fl vs 2f+heroic",       "d=ggAAAAAAIAA&a1=MwgAAAAAAAA",                     1.391961872577667 },
    { "3fl+Han vs 0",           "d=AAAAAAAAAAAA&a1=MwgAAAsAAAA",                    2.891601562500000 },
    { "3f vs 1+LW+Han",         "d=AQAABA4AAAAA&a1=MQgAAAAAAAA",                    1.505950927734375 },
];

// State set is cleared - merely passed in to reuse memory
private SimulationResults run_test(string form_string)
{
    // Super simple form string parsing... good enough for our purposes here
    // TODO: See if it's worth getting rid of the GC here eventually.
    string[string] params_map;
    foreach (param; form_string.splitter('&'))
    {
        auto split = param.findSplit("=");
        assert(split.length == 3);              // a#=????
        params_map[split[0]] = split[2];
    }

    auto defense_form = create_form_from_url!DefenseForm(params_map["d"]);
    TokenState defense_tokens = defense_form.to_defense_tokens2();

    SimulationState initial_state = SimulationState.init;
    initial_state.defense_tokens   = defense_tokens;
    initial_state.probability      = 1.0;

    // TODO: Could avoid allocating new ones of these for each attack, but currently
    // "simulate_attack" allocates a new one internally, so not worth the effort right now.
    auto states = new SimulationStateSet();
    states.push_back(initial_state);

    foreach (i; 0 .. 6)
    {
        string param = "a" ~ to!string(i + 1);
        if (!(param in params_map)) continue;

        auto attack_form = create_form_from_url!AttackForm(params_map[param], i);
        if (attack_form.enabled)
        {
            TokenState attack_tokens = to_attack_tokens2(attack_form);
            states.replace_attack_tokens(attack_tokens);

            SimulationSetup setup = to_simulation_setup(attack_form, defense_form);
            states = simulate_attack(setup, states);
        }
    }

    return states.compute_results();
}

// NOTE: These aren't really unit tests, but we're piggy-backing off of the convenience of "dub test" for now.
unittest
{
    SimulationState initial_state = SimulationState.init;
    initial_state.probability      = 1.0;

    foreach (ref test; k_regression_test_cases)
    {
        auto sw = StopWatch(AutoStart.yes);

        auto results = run_test(test.form_string);
        double expected_damage = results.total_sum.hits + results.total_sum.crits;

        if (abs(expected_damage - test.expected_damage) > k_expected_damage_epsilon)
        {
            writefln("Test '%s': FAILED. Expected %.15f got %.15f. %s",
                     test.name, test.expected_damage, expected_damage, test.form_string);
            assert(false);
        }
        else
        {
            writefln("Test '%s': PASSED (%sms)", test.name, sw.peek().total!"msecs");
        }
    }
}
