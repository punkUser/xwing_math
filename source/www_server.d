import simulation;

import std.stdio;
import std.uni;
import std.stdint;

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

    private void index(HTTPServerRequest req, HTTPServerResponse res)
    {
        AttackSetup attack_setup;
        DefenseSetup defense_setup;

        attack_setup.dice = 4;
        defense_setup.dice = 4;
        defense_setup.evade_token_count = 0;

        immutable kTrialCount = 1000000;

        SimulationResult total_result;
        SimulationResult[kMaxDice] total_hits_pdf;
        foreach (i; 0 .. kTrialCount)
        {
            auto result = simulate_attack(attack_setup, defense_setup);
            total_result = accumulate_result(total_result, result);

            // Accumulate into the right bin of the total hits PDF
            int total_hits = result.hits + result.crits;
            total_hits_pdf[total_hits] = accumulate_result(total_hits_pdf[total_hits], result);
        }

        string[] content = [
            format("E[Hits]: %s", cast(double)total_result.hits / total_result.trial_count),
            format("E[Crits]: %s", cast(double)total_result.crits / total_result.trial_count),
            format("E[Total]: %s", cast(double)(total_result.hits + total_result.crits) / total_result.trial_count)
        ];

        // Inverse CDF:
        // total_hits_cdf[x] = pdf(i >= x)
        SimulationResult[kMaxDice] total_hits_inv_cdf;
        total_hits_inv_cdf[kMaxDice-1] = total_hits_pdf[kMaxDice-1];
        for (int i = kMaxDice-2; i >= 0; --i)
            total_hits_inv_cdf[i] = accumulate_result(total_hits_inv_cdf[i+1], total_hits_pdf[i]);

        foreach (i; 1 .. attack_setup.dice + 1)
            content ~= format("P(total_hits >= %s) = %s", i, cast(double)total_hits_inv_cdf[i].trial_count / kTrialCount);
        
        res.render!("index.dt", content);
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
