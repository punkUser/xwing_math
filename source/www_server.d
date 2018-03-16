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
        auto settings = new HTTPServerSettings;
        settings.errorPageHandler = toDelegate(&error_page);
        settings.port = 80;

        //settings.sessionStore = new MemorySessionStore();

        //settings.accessLogFormat = "%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-Agent}i\" %D";
        //settings.accessLogToConsole = true;

        auto router = new URLRouter;
    
        router.get("/", &basic);
        router.get("/advanced/", &advanced);
        router.get("/alpha/", &alpha);
        router.get("/faq/", &about);
        router.get("/about/", staticRedirect("/faq/", HTTPStatus.movedPermanently));
        router.post("/simulate_basic.json", &simulate_basic);
        router.post("/simulate_advanced.json", &simulate_advanced);
        router.post("/simulate_alpha.json", &simulate_alpha);
    
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

        router.get("*", serveStaticFiles("./public/"));    

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
            writefln("%s -> %s", req.fullURL(), url);
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
            log_message("%s %s Simulated %s states in %s msec",
                        req.clientAddress.toAddressString(),
                        "/?q=" ~ form_state_string,
                        results.total_sum.evaluation_count, sw.peek().total!"msecs");
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
            log_message("%s %s Simulated %s states in %s msec",
                        req.clientAddress.toAddressString(),
                        "/advanced/?q=" ~ form_state_string,
                        results.total_sum.evaluation_count, sw.peek().total!"msecs");
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
            content.results[i] = assemble_json_result(results_after_attack[i], min_hits);

        res.writeJsonBody(content);
    }

    private SimulateJsonContent.Result assemble_json_result(
        ref const(SimulationResults) results,
        int min_hits = 7)
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

        // Tokens (see labels above)
        string[] exp_token_labels = ["Focus", "Target Lock", "Evade", "Stress"];
        double[] exp_attack_tokens = [
            results.total_sum.attack_delta_focus_tokens,
            results.total_sum.attack_delta_target_locks,
            0.0f,
            results.total_sum.attack_delta_stress];
        double[] exp_defense_tokens = [
            results.total_sum.defense_delta_focus_tokens,
            0.0f,
            results.total_sum.defense_delta_evade_tokens,
            results.total_sum.defense_delta_stress];

        // Tokens that we only show if they changed
        // NOTE: This is not perfect in cases where it just happens to average out to exactly 0, but
        // there are no cases where it can be positive for these "tokens" (really cards) at the moment.
        if (results.total_sum.attack_delta_crack_shot != 0.0)
        {
            exp_token_labels    ~= "Crack Shot";
            exp_attack_tokens   ~= results.total_sum.attack_delta_crack_shot;
            exp_defense_tokens  ~= 0.0;     // N/A
        }

        if (results.total_sum.defense_delta_harpooned != 0.0)
        {
            exp_token_labels    ~= "Harpooned!";
            exp_attack_tokens   ~= 0.0;     // N/A
            exp_defense_tokens  ~= results.total_sum.defense_delta_harpooned;
        }

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
            token_html.compileHTMLDietFile!("token_table.dt", exp_token_labels, exp_attack_tokens, exp_defense_tokens);
            content.token_table_html = token_html.data;
        }

        return content;
    }

    private void basic(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        BasicForm form_values = create_form_from_url!BasicForm(form_state_string);
        res.render!("basic.dt", form_values);
    }

    private void advanced(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        AdvancedForm form_values = create_form_from_url!AdvancedForm(form_state_string);
        res.render!("advanced.dt", form_values);
    }

    private void alpha(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        AlphaForm form_values = create_form_from_url!AlphaForm(form_state_string);
        res.render!("alpha.dt", form_values);
    }

    private void about(HTTPServerRequest req, HTTPServerResponse res)
    {
        res.render!("about.dt");
    }

    // *************************************** ERROR ************************************************

    private void error_page(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
    {
        // To be extra safe we avoid DB queries in the error page for now
        //auto recent_tournaments = m_data_store.tournaments(true);

        res.render!("error.dt", req, error);
    }


    // *************************************** State ************************************************

    // NOTE: Be a bit careful with state here. These functions can be parallel and re-entrant due to
    // triggering blocking calls and then having other requests submitted by separate fibers.
}
