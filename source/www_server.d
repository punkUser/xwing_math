import simulation;

import std.stdio;
import std.uni;
import std.stdint;
import std.algorithm;
import std.random;

import vibe.d;

public class WWWServer
{
    public this()
    {
        auto settings = new HTTPServerSettings;
        settings.errorPageHandler = toDelegate(&error_page);
        settings.port = 8080;

        //settings.sessionStore = new MemorySessionStore();
        //settings.accessLogFile = m_config.http_server_log_file;

	    auto router = new URLRouter;
    
        router.get("/", &index);
        router.get("/simulate.json", &simulate);
	
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
            req.path ~= "/";
            auto url = req.fullURL();
            res.redirect(url, status);
	    };
    }

    private struct SimulationContent
    {
        float expected_total_hits;
        string[] pdf_x_labels;
        float[] hit_pdf;
        float[] crit_pdf;
        float[] hit_inv_cdf;

        string[4] exp_token_labels;
        float[4] exp_attack_tokens;
        float[4] exp_defense_tokens;
    };

    private void simulate(HTTPServerRequest req, HTTPServerResponse res)
    {
        //writeln(req.query.serializeToPrettyJson());

        

		/*************************************************************************************************/
		AttackSetup attack_setup;

        attack_setup.dice                = to!int(req.query.get("attack_dice",              "3"));
        attack_setup.tokens.focus        = to!int(req.query.get("attack_focus_token_count", "0"));
        attack_setup.tokens.target_lock  = to!int(req.query.get("attack_target_lock_count", "0"));
        
		// Add results
		attack_setup.add_hit_count       += (req.query.get("attack_fearlessness", "")       == "on") ? 1 : 0;
		attack_setup.add_blank_count     += (req.query.get("attack_finn", "")               == "on") ? 1 : 0;

		// Rerolls
		attack_setup.any_reroll_count    += (req.query.get("attack_predator_1", "")         == "on") ? 1 : 0;
		attack_setup.any_reroll_count    += (req.query.get("attack_predator_2", "")         == "on") ? 2 : 0;
		attack_setup.any_reroll_count    += (req.query.get("attack_rage", "")               == "on") ? 3 : 0;
		attack_setup.blank_reroll_count  += (req.query.get("attack_rey", "")				== "on") ? 2 : 0;
		attack_setup.focus_reroll_count  += (req.query.get("attack_wired", "")				== "on") ? attack_setup.dice : 0;


		// Change results
		// TODO: Verify this is always correct for marksmanship... in practice the entire effect must be applied at once
		attack_setup.focus_to_crit_count += (req.query.get("attack_marksmanship", "")       == "on") ? 1 : 0;
		attack_setup.focus_to_hit_count  += (req.query.get("attack_marksmanship", "")       == "on") ? attack_setup.dice : 0;
		attack_setup.focus_to_hit_count  += (req.query.get("attack_expertise", "")          == "on") ? attack_setup.dice : 0;
		attack_setup.hit_to_crit_count   += (req.query.get("attack_mercenary_copilot", "")  == "on") ? 1 : 0;
		attack_setup.hit_to_crit_count   += (req.query.get("attack_mangler_cannon", "")     == "on") ? 1 : 0;
        
		attack_setup.heavy_laser_cannon  = req.query.get("attack_heavy_laser_cannon", "")   == "on";        
		attack_setup.juke                = req.query.get("attack_juke", "")                 == "on";
        attack_setup.accuracy_corrector  = req.query.get("attack_accuracy_corrector", "")   == "on";
        attack_setup.fire_control_system = req.query.get("attack_fire_control_system", "")  == "on";
		attack_setup.one_damage_on_hit   = req.query.get("attack_one_damage_on_hit", "")    == "on";



		/*
		attack_setup.rey                 = req.query.get("attack_rey", "")					== "on";

        attack_setup.expertise           = req.query.get("attack_expertise", "")            == "on";
        attack_setup.fearlessness        = req.query.get("attack_fearlessness", "")         == "on";
        attack_setup.juke                = req.query.get("attack_juke", "")                 == "on";
        attack_setup.predator_rerolls =
            req.query.get("attack_predator_1", "") == "on" ? 1 : 
            (req.query.get("attack_predator_2", "") == "on" ? 2 : 0);
        attack_setup.rage                = req.query.get("attack_rage", "")                 == "on";
        attack_setup.wired               = req.query.get("attack_wired", "")                == "on";

        attack_setup.mercenary_copilot   = req.query.get("attack_mercenary_copilot", "")    == "on";
        attack_setup.finn                = req.query.get("attack_finn", "")                 == "on";
        
        attack_setup.heavy_laser_cannon  = req.query.get("attack_heavy_laser_cannon", "")   == "on";        
        attack_setup.mangler_cannon      = req.query.get("attack_mangler_cannon", "")       == "on";
        attack_setup.marksmanship        = req.query.get("attack_marksmanship", "")         == "on";
        attack_setup.one_damage_on_hit   = req.query.get("attack_one_damage_on_hit", "")    == "on";

        attack_setup.accuracy_corrector  = req.query.get("attack_accuracy_corrector", "")   == "on";
        attack_setup.fire_control_system = req.query.get("attack_fire_control_system", "")  == "on";
		*/

		/*************************************************************************************************/
        DefenseSetup defense_setup;

        defense_setup.dice            = to!int(req.query.get("defense_dice",              "3"));
        defense_setup.tokens.focus    = to!int(req.query.get("defense_focus_token_count", "0"));
        defense_setup.tokens.evade    = to!int(req.query.get("defense_evade_token_count", "0"));

		defense_setup.rey             = req.query.get("defense_rey", "")				  == "on";
        defense_setup.wired           = req.query.get("defense_wired", "")                == "on";
        defense_setup.finn            = req.query.get("defense_finn", "")                 == "on";
        defense_setup.sensor_jammer   = req.query.get("defense_sensor_jammer", "")        == "on";
        defense_setup.autothrusters   = req.query.get("defense_autothrusters", "")        == "on";
        

		/*************************************************************************************************/
		// Bit awkward but good enough for now...
        string attack_type = req.query.get("attack_type", "single");
        if (attack_type == "single")
            attack_setup.type = MultiAttackType.Single;
        else if (attack_type == "secondary_perform_twice")
            attack_setup.type = MultiAttackType.SecondaryPerformTwice;
        else if (attack_type == "after_attack_does_not_hit")
            attack_setup.type = MultiAttackType.AfterAttackDoesNotHit;
        else if (attack_type == "after_attack")
            attack_setup.type = MultiAttackType.AfterAttack;
        else
            assert(false);

		/*************************************************************************************************/

        //writefln("Attack Setup: %s", attack_setup.serializeToPrettyJson());
        //writefln("Defense Setup: %s", defense_setup.serializeToPrettyJson());

        auto simulation = new Simulation(attack_setup, defense_setup);


		// Exhaustive search
        {            
            auto sw = StopWatch(AutoStart.yes);

            simulation.simulate_attack_exhaustive();

            writefln("Exhaustive simulation: %d evaluations in %s msec",
                     simulation.total_sum().evaluation_count, sw.peek().msecs());
        }

        auto total_hits_pdf = simulation.total_hits_pdf();
        auto total_sum = simulation.total_sum();

        int max_hits = cast(int)total_hits_pdf.length;


        // Setup page content
        SimulationContent content;
        
        // Expected values
        content.expected_total_hits = (total_sum.hits + total_sum.crits);

        // Set up X labels on the total hits graph
        content.pdf_x_labels = new string[max_hits];
        foreach (i; 0 .. max_hits)
            content.pdf_x_labels[i] = to!string(i);

        // Compute PDF
        // TODO: Move some of this to simulation helpers?
        content.hit_pdf     = new float[max_hits];
        content.crit_pdf    = new float[max_hits];
        content.hit_inv_cdf = new float[max_hits];
        foreach (i; 0 .. max_hits)
        {
            float total = total_hits_pdf[i].hits + total_hits_pdf[i].crits;
            float fraction_crits = total > 0.0f ? total_hits_pdf[i].crits / total : 0.0f;
            float fraction_hits  = 1.0f - fraction_crits;

            content.hit_pdf[i]  = 100.0f * fraction_hits  * total_hits_pdf[i].probability;
            content.crit_pdf[i] = 100.0f * fraction_crits * total_hits_pdf[i].probability;
        }

        // Compute inverse CDF P(at least X hits)
        content.hit_inv_cdf[max_hits-1] = content.hit_pdf[max_hits-1] + content.crit_pdf[max_hits-1];
        for (int i = max_hits-2; i >= 0; --i)
        {
            content.hit_inv_cdf[i] = content.hit_inv_cdf[i+1] + content.hit_pdf[i] + content.crit_pdf[i];
        }

        // Tokens (see labels above)
        content.exp_token_labels = ["Focus", "Target Lock", "Evade", "Stress"];
        content.exp_attack_tokens = [
            total_sum.attack_delta_focus_tokens,
            total_sum.attack_delta_target_locks,
            0.0f,
            total_sum.attack_delta_stress];
        content.exp_defense_tokens = [
            total_sum.defense_delta_focus_tokens,
            0.0f,
            total_sum.defense_delta_evade_tokens,
            total_sum.defense_delta_stress];

        res.writeJsonBody(content);
    }


    private void index(HTTPServerRequest req, HTTPServerResponse res)
    {
        res.render!("index.dt");
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
