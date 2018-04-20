import simulation;
import simulation_state;
import form;
import basic_form;
import advanced_form;
import alpha_form;
import log;

import std.array;
import std.stdio;
import std.datetime;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.algorithm;

import vibe.d;
import diet.html;

public class WWWServer
{
    public this()
    {
        m_server_settings.url_root = "/";

        auto settings = new HTTPServerSettings;
        settings.errorPageHandler = toDelegate(&error_page);
        settings.port = 80;

        //settings.accessLogFormat = "%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-Agent}i\" %D";
        //settings.accessLogToConsole = true;

        auto router = new URLRouter;
    
        router.get (m_server_settings.url_root, &basic);
        router.post(m_server_settings.url_root ~ "simulate.json", &simulate_basic);

        router.get (m_server_settings.url_root ~ "advanced/", &advanced);
        router.post(m_server_settings.url_root ~ "advanced/simulate.json", &simulate_advanced);

        router.get (m_server_settings.url_root ~ "alpha/", &alpha);
        router.post(m_server_settings.url_root ~ "alpha/simulate.json", &simulate_alpha);

        router.get (m_server_settings.url_root ~ "faq/", &about);
        router.get (m_server_settings.url_root ~ "about/", staticRedirect(m_server_settings.url_root ~ "faq/", HTTPStatus.movedPermanently));
            
        debug
        {
            // Show routes in debug for convenience
            foreach (route; router.getAllRoutes()) {
                writeln(route);
            }
        }
        else
        {
            // Add a redirect from each GET route without a trailing slash for robustness
            // Leave this disabled in debug/dev builds so we don't accidentally include non-canonical links
            foreach (route; router.getAllRoutes()) {
                if (route.method == HTTPMethod.GET && route.pattern.length > 1 && route.pattern.endsWith("/")) {
                    router.get(route.pattern[0..$-1], redirect_append_slash());
                }
            }
        }

        auto file_server_settings = new HTTPFileServerSettings;
        file_server_settings.serverPathPrefix = m_server_settings.url_root;
        router.get(m_server_settings.url_root ~ "*", serveStaticFiles("./public/", file_server_settings));

        listenHTTP(settings, router);
    }

    // Handy utility for adding some robustness to routes
    // NOTE: Be careful with this for paths that might contain query strings or other nastiness
    private HTTPServerRequestDelegate redirect_append_slash(HTTPStatus status = HTTPStatus.found)
    {
        return (HTTPServerRequest req, HTTPServerResponse res) {
            // This is a bit awkward but seems to do the trick for the moment...
            auto url = req.fullURL();
            auto path = url.path;
            path.endsWithSlash = true;

            url.path = path;
            //writefln("%s -> %s", req.fullURL(), url);
            res.redirect(url, status);
        };
    }

    private struct SimulateJsonContent
    {
        struct Result
        {
            double expected_total_hits;
            double at_least_one_crit;       // Percent

            // PDF/CDF chart
            string[] pdf_x_labels;
            double[] hit_pdf;               // Percent
            double[] crit_pdf;              // Percent
            double[] hit_inv_cdf;           // Percent
            string pdf_table_html;          // HTML for data table

            // Token chart
            string[] exp_token_labels;
            double[] exp_attack_tokens;
            double[] exp_defense_tokens;
            string token_table_html;        // HTML for data table
        };

        Result[] results;

        // Query string that can be used in the URL to get back to the form state that generated this
        string form_state_string;
    };

    private void simulate_basic(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.form.serializeToPrettyJson());

        auto basic_form = create_form_from_fields!BasicForm(req.form);
        string form_state_string = serialize_form_to_url(basic_form);

        SimulationSetup setup        = basic_form.to_simulation_setup();
        TokenState attack_tokens     = basic_form.to_attack_tokens();
        TokenState defense_tokens    = basic_form.to_defense_tokens();
        
        SimulationResults results;
        {
            auto sw = StopWatch(AutoStart.yes);

            auto simulation = new Simulation(attack_tokens, defense_tokens);
            simulation.simulate_attack(setup);
            results = simulation.compute_results();

            // NOTE: This is kinda similar to the access log, but convenient for now
            log_message("%s %s Simulated in %s msec",
                        req.clientAddress.toAddressString(),
                        "/?q=" ~ form_state_string,
                        sw.peek().total!"msecs");
        }

        SimulateJsonContent content;
        content.form_state_string = form_state_string;
        content.results = new SimulateJsonContent.Result[1];
        content.results[0] = assemble_json_result(results);
        res.writeJsonBody(content);
    }

    private void simulate_advanced(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.form.serializeToPrettyJson());

        auto advanced_form = create_form_from_fields!AdvancedForm(req.form);
        string form_state_string = serialize_form_to_url(advanced_form);

        SimulationSetup setup       = advanced_form.to_simulation_setup();
        TokenState attack_tokens    = advanced_form.to_attack_tokens();
        TokenState defense_tokens   = advanced_form.to_defense_tokens();

        SimulationResults results;
        {
            auto sw = StopWatch(AutoStart.yes);

            auto simulation = new Simulation(attack_tokens, defense_tokens);
            simulation.simulate_attack(setup);
            results = simulation.compute_results();

            // NOTE: This is kinda similar to the access log, but convenient for now
            log_message("%s %s Simulated in %s msec",
                        req.clientAddress.toAddressString(),
                        "/advanced/?q=" ~ form_state_string,
                        sw.peek().total!"msecs");
        }

        SimulateJsonContent content;
        content.form_state_string = form_state_string;
        content.results = new SimulateJsonContent.Result[1];
        content.results[0] = assemble_json_result(results);
        res.writeJsonBody(content);
    }

    private void simulate_alpha(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.form.serializeToPrettyJson());

        auto alpha_form = create_form_from_fields!AlphaForm(req.form);
        string form_state_string = serialize_form_to_url(alpha_form);

        // Save results for each attack as we accumulate
        int max_enabled_attack = 1;
        SimulationResults[5] results_after_attack;
        {
            auto sw = StopWatch(AutoStart.yes);

            TokenState defense_tokens = alpha_form.to_defense_tokens();

            auto simulation = new Simulation(TokenState.init, defense_tokens);

            // NOTE: Every attack is the "final" one for the attacker, since these are modeled as
            // separate attackers with separate token usage.
            int defender_final_attack = 0;
            if      (alpha_form.a5_enabled) defender_final_attack = 5;
            else if (alpha_form.a4_enabled) defender_final_attack = 4;
            else if (alpha_form.a3_enabled) defender_final_attack = 3;
            else if (alpha_form.a2_enabled) defender_final_attack = 2;
            else if (alpha_form.a1_enabled) defender_final_attack = 1;

            // TODO: Refactor and add separate perf timings to each attack for logging purposes            
            if (alpha_form.a1_enabled)
            {
                SimulationSetup setup_1 = alpha_form.to_simulation_setup!"a1"();
                simulation.replace_attack_tokens(alpha_form.to_attack_tokens!"a1"());
                simulation.simulate_attack(setup_1, true, (defender_final_attack == 1));
                max_enabled_attack = 1;
            }
            results_after_attack[0] = simulation.compute_results();
            if (alpha_form.a2_enabled)
            {
                SimulationSetup setup_2 = alpha_form.to_simulation_setup!"a2"();
                simulation.replace_attack_tokens(alpha_form.to_attack_tokens!"a2"());
                simulation.simulate_attack(setup_2, true, (defender_final_attack == 2));
                max_enabled_attack = 2;
            }
            results_after_attack[1] = simulation.compute_results();
            if (alpha_form.a3_enabled)
            {
                SimulationSetup setup_3 = alpha_form.to_simulation_setup!"a3"();
                simulation.replace_attack_tokens(alpha_form.to_attack_tokens!"a3"());
                simulation.simulate_attack(setup_3, true, (defender_final_attack == 3));
                max_enabled_attack = 3;
            }
            results_after_attack[2] = simulation.compute_results();
            if (alpha_form.a4_enabled)
            {
                SimulationSetup setup_4 = alpha_form.to_simulation_setup!"a4"();
                simulation.replace_attack_tokens(alpha_form.to_attack_tokens!"a4"());
                simulation.simulate_attack(setup_4, true, (defender_final_attack == 4));
                max_enabled_attack = 4;
            }
            results_after_attack[3] = simulation.compute_results();
            if (alpha_form.a5_enabled)
            {
                SimulationSetup setup_5 = alpha_form.to_simulation_setup!"a5"();
                simulation.replace_attack_tokens(alpha_form.to_attack_tokens!"a5"());
                simulation.simulate_attack(setup_5, true, (defender_final_attack == 5));
                max_enabled_attack = 5;
            }
            results_after_attack[4] = simulation.compute_results();

            // NOTE: This is kinda similar to the access log, but convenient for now
            log_message("%s %s Simulated in %s msec",
                        req.clientAddress.toAddressString(),
                        "/alpha/?q=" ~ form_state_string,
                        sw.peek().total!"msecs");
        }

        SimulateJsonContent content;
        content.form_state_string = form_state_string;

        // NOTE: max_enabled_attack is 1-based
        content.results = new SimulateJsonContent.Result[max_enabled_attack];
        
        // Make sure all the graphs/tables have the same dimensions (worst case)
        int min_hits = 7;
        foreach(i; 0 .. max_enabled_attack)
            min_hits = max(min_hits, cast(int)results_after_attack[i].total_hits_pdf.length);

        foreach(i; 0 .. max_enabled_attack)
            content.results[i] = assemble_json_result(results_after_attack[i], min_hits, i);

        res.writeJsonBody(content);
    }

    private SimulateJsonContent.Result assemble_json_result(
        ref const(SimulationResults) results,
        int min_hits = 7,
        int attacker_index = -1, int defender_index = -1)
    {
        SimulateJsonContent.Result content;

        // Always nice to show at least 0..6 hits on the graph
        int graph_max_hits = max(min_hits, cast(int)results.total_hits_pdf.length);

        content.expected_total_hits = (results.total_sum.hits + results.total_sum.crits);
        content.at_least_one_crit = 100.0 * results.at_least_one_crit_probability;

        // Set up X labels on the total hits graph
        content.pdf_x_labels = new string[graph_max_hits];
        foreach (i; 0 .. graph_max_hits)
            content.pdf_x_labels[i] = to!string(i);

        // Compute PDF for graph
        content.hit_pdf     = new double[graph_max_hits];
        content.crit_pdf    = new double[graph_max_hits];
        content.hit_inv_cdf = new double[graph_max_hits];

        content.hit_pdf[] = 0.0;
        content.crit_pdf[] = 0.0;
        content.hit_inv_cdf[] = 0.0;

        foreach (int i, SimulationResult result; results.total_hits_pdf)
        {
            double total_probability = result.hits + result.crits;
            double fraction_crits = total_probability > 0.0 ? result.crits / total_probability : 0.0;
            double fraction_hits  = 1.0 - fraction_crits;

            content.hit_pdf[i]  = 100.0 * fraction_hits  * result.probability;
            content.crit_pdf[i] = 100.0 * fraction_crits * result.probability;
        }

        // Compute inverse CDF P(at least X hits)
        content.hit_inv_cdf[graph_max_hits-1] = content.hit_pdf[graph_max_hits-1] + content.crit_pdf[graph_max_hits-1];
        for (int i = graph_max_hits-2; i >= 0; --i)
        {
            content.hit_inv_cdf[i] = content.hit_inv_cdf[i+1] + content.hit_pdf[i] + content.crit_pdf[i];
        }

        // Tokens
        string[TokenDelta.field_count()] token_labels;
        double[TokenDelta.field_count()] attack_tokens;
        double[TokenDelta.field_count()] defense_tokens;
        size_t token_field_count = 0;

        foreach (i; 0 .. token_labels.length)
        {
            double attack  = results.total_sum.attack_token_delta.delta(i);
            double defense = results.total_sum.defense_token_delta.delta(i);
            if (attack != 0.0 || defense != 0.0)
            {
                assert(token_field_count <= token_labels.length);
                token_labels[token_field_count]   = TokenDelta.field_name(i);
                attack_tokens[token_field_count]  = attack;
                defense_tokens[token_field_count] = defense;
                ++token_field_count;
            }
        }

        auto exp_token_labels = token_labels[0 .. token_field_count].dup;
        auto exp_attack_tokens = attack_tokens[0 .. token_field_count].dup;
        auto exp_defense_tokens = defense_tokens[0 .. token_field_count].dup;

        content.exp_token_labels   = exp_token_labels;
        content.exp_attack_tokens  = exp_attack_tokens;
        content.exp_defense_tokens = exp_defense_tokens;

        // Render HTML for tables
        {
            SimulationResult[] total_hits_pdf = results.total_hits_pdf.dup;
            if (total_hits_pdf.length < min_hits)
                total_hits_pdf.length = min_hits;

            auto pdf_html = appender!string();
            pdf_html.compileHTMLDietFile!("pdf_table.dt", total_hits_pdf);
            content.pdf_table_html = pdf_html.data;
        }
        {
            auto token_html = appender!string();
            token_html.compileHTMLDietFile!("token_table.dt", exp_token_labels, exp_attack_tokens, exp_defense_tokens, attacker_index, defender_index);
            content.token_table_html = token_html.data;
        }

        return content;
    }

    private void basic(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        BasicForm form_values = create_form_from_url!BasicForm(form_state_string);

        auto server_settings = m_server_settings;
        res.render!("basic.dt", server_settings, form_values);
    }

    private void advanced(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        AdvancedForm form_values = create_form_from_url!AdvancedForm(form_state_string);

        auto server_settings = m_server_settings;
        res.render!("advanced.dt", server_settings, form_values);
    }

    private void alpha(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        AlphaForm form_values = create_form_from_url!AlphaForm(form_state_string);

        auto server_settings = m_server_settings;
        res.render!("alpha.dt", server_settings, form_values);
    }

    private void about(HTTPServerRequest req, HTTPServerResponse res)
    {
        auto server_settings = m_server_settings;
        res.render!("about.dt", server_settings);
    }

    // *************************************** ERROR ************************************************

    private void error_page(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
    {
        auto server_settings = m_server_settings;
        res.render!("error.dt", server_settings, req, error);
    }


    // *************************************** State ************************************************

    // NOTE: Be a bit careful with state here. These functions can be parallel and re-entrant due to
    // triggering blocking calls and then having other requests submitted by separate fibers.

    struct ServerSettings
    {
        string url_root = "/";
    };
    immutable ServerSettings m_server_settings;
}
