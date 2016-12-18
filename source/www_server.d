import simulation;

import std.stdio;
import std.uni;
import std.stdint;
import std.algorithm;

import vibe.d;

public class WWWServer
{
    public this()
    {
        auto settings = new HTTPServerSettings;
        settings.errorPageHandler = toDelegate(&error_page);
        settings.port = 80;
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
        float[] hit_pdf;
        float[] crit_pdf;
        float[] hit_inv_cdf;
    };

    private void simulate(HTTPServerRequest req, HTTPServerResponse res)
    {
        //writeln(req.query);

        AttackSetup attack_setup;
        DefenseSetup defense_setup;

        attack_setup.dice               = to!int(req.query.get("attack_dice",              "3"));
        attack_setup.focus_token_count  = to!int(req.query.get("attack_focus_token_count", "0"));
        attack_setup.target_lock_count  = to!int(req.query.get("attack_target_lock_count", "0"));
        
        // Checkboxes will simply not be present in the parameters if unchecked
        attack_setup.accuracy_corrector  = req.query.get("attack_accuracy_corrector", "")   == "on";
        attack_setup.juke                = req.query.get("attack_juke", "")                 == "on";
        attack_setup.fire_control_system = req.query.get("attack_fire_control_system", "")  == "on";

        // Bit awkward but good enough for now...
        string attack_type = req.query.get("attack_type", "single");
        if      (attack_type == "single")                     attack_setup.type = MultiAttackType.Single;
        else if (attack_type == "secondary_perform_twice")    attack_setup.type = MultiAttackType.SecondaryPerformTwice;
        else if (attack_type == "after_attack_does_not_hit")  attack_setup.type = MultiAttackType.AfterAttackDoesNotHit;
        else if (attack_type == "after_attack")               attack_setup.type = MultiAttackType.AfterAttack;
        else assert(false);

        defense_setup.dice              = to!int(req.query.get("defense_dice",              "3"));
        defense_setup.focus_token_count = to!int(req.query.get("defense_focus_token_count", "0"));
        defense_setup.evade_token_count = to!int(req.query.get("defense_evade_token_count", "0"));

        // TODO: Clean this up? Max hits is kind of unpredictable though TBH
        immutable int k_trial_count = 500000;
        immutable int max_hits = 10;

        SimulationResult[] total_hits_pdf = new SimulationResult[max_hits];
        foreach (i; 0 .. k_trial_count)
        {
            auto result = simulate_attack(attack_setup, defense_setup);

            // Accumulate into the right bin of the total hits PDF
            int total_hits = result.hits + result.crits;
            total_hits_pdf[total_hits] = accumulate_result(total_hits_pdf[total_hits], result);
        }

        // Setup page content
        SimulationContent content;
        content.hit_pdf     = new float[max_hits];
        content.crit_pdf    = new float[max_hits];
        content.hit_inv_cdf = new float[max_hits];

        // Compute PDF
        float percent_of_trials_scale = 100.0f / cast(float)k_trial_count;
        foreach (i; 0 .. max_hits)
        {
            auto bar_height = total_hits_pdf[i].trial_count * percent_of_trials_scale;
            auto percent_crits = total_hits_pdf[i].crits / max(1.0f, cast(float)(total_hits_pdf[i].hits + total_hits_pdf[i].crits));
            auto percent_hits  = 1.0f - percent_crits;
            content.hit_pdf[i]  = bar_height * percent_hits ;
            content.crit_pdf[i] = bar_height * percent_crits;
        }

        // Compute inverse CDF P(at least X hits)
        content.hit_inv_cdf[max_hits-1] = content.hit_pdf[max_hits-1] + content.crit_pdf[max_hits-1];
        for (int i = max_hits-2; i >= 0; --i)
        {
            content.hit_inv_cdf[i] = content.hit_inv_cdf[i+1] + content.hit_pdf[i] + content.crit_pdf[i];
        }

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
