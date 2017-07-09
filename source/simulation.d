module simulation;

import std.algorithm;
import std.random;
import std.stdio;
import std.math;

public immutable k_die_sides = 8;

enum DieResult : int
{
    Blank = 0,
    Hit,
    Crit,
    Focus,
    Evade,
    Num
};
immutable DieResult[k_die_sides] k_attack_die_result = [
    DieResult.Blank, DieResult.Blank,
    DieResult.Focus, DieResult.Focus,
    DieResult.Hit, DieResult.Hit, DieResult.Hit,
    DieResult.Crit
];
immutable DieResult[k_die_sides] k_defense_die_result = [
    DieResult.Blank, DieResult.Blank, DieResult.Blank,
    DieResult.Focus, DieResult.Focus,
    DieResult.Evade, DieResult.Evade, DieResult.Evade
];

enum MultiAttackType : int
{
    Single = 0,                   // Regular single attack
    SecondaryPerformTwice,        // Ex. Twin Laser Turret, Cluster Missiles
    AfterAttackDoesNotHit,        // Ex. Gunner, Luke, IG88-B - TODO: Luke Gunner modeling somehow?
    AfterAttack,                  // Ex. Corran    
};

struct TokenState
{
    int focus = 0;
    int evade = 0;
    int target_lock = 0;
    int stress = 0;
}

struct AttackSetup
{
    MultiAttackType type = MultiAttackType.Single;

    // Tokens
    int dice = 0;
    TokenState tokens;

	// Mod attack dice abilities

	// Add results
	int add_hit_count = 0;
	int add_crit_count = 0;
	int add_blank_count = 0;
	int add_focus_count = 0;

	// Rerolls
	int any_reroll_count = 0;
	int blank_reroll_count = 0;
	int focus_reroll_count = 0;

	// Change results
	//int any_to_crit_count = 0;
	//int any_to_hit_count = 0;
	int focus_to_crit_count = 0;
	int focus_to_hit_count = 0;
	int blank_to_crit_count = 0;
	int blank_to_hit_count = 0;
	int hit_to_crit_count = 0;
	



	// Mod defense dice abilities



    // Pilots
	//bool rey = false;					// Reroll up to 2 blanks

    // EPT
    bool juke = false;                  // Setting this to true implies evade token present as well
    //bool marksmanship = false;          // One focus->crit, rest focus->hit
    //int  predator_rerolls = 0;          // 0-2 rerolls
    //bool rage = false;                  // 3 rerolls
    //bool wired = false;                 // reroll any/all focus
    //bool expertise = false;             // all focus -> hits
    //bool fearlessness = false;          // add 1 hit result
    // TODO: Lone wolf (1 blank reroll)
    // TODO: Crack shot? (gets a little bit complex as presence affects defender logic and as well)

    // Crew
    //bool mercenary_copilot = false;     // One hit->crit
    //bool finn = false;                  // Add one blank result to roll
    // TODO: Ezra Crew (one focus->crit)
    // TODO: Zuckuss Crew
    // TODO: 4-LOM Crew
    // TODO: Dengar Crew (overlaps w/ EPT rerolls...)
    // TODO: Bossk Crew (gets weird/hard...)
    // TODO: Hot shot copilot
    // TODO: Captain rex (only affects multi-attack)
    // TODO: Operations specialist? Again only multi-attack
    // TODO: Bistain (hit -> crit, like merc copilot)

    // System upgrades
    bool accuracy_corrector = false;    // Can cancel all results and replace with 2 hits    
    bool fire_control_system = false;   // Get a target lock after attack (only affects multi-attack)
    
    // Secondary weapons
    bool heavy_laser_cannon = false;    // After initial roll, change all crits->hits
    //bool mangler_cannon = false;        // One hit->crit
    bool one_damage_on_hit = false;     // If attack hits, 1 damage (TLT, Ion, etc)
    // TODO: Autoblaster (hit results cannot be canceled)
    
    // Ones that require spending tokens (more complex generally)
    // TODO: Calculation (pay focus: one focus->crit)
    // TODO: Han Solo Crew (spend TL: all hits->crits)
    // TODO: R4 Agromech (after spending focus, gain TL that can be used in same attack)
};

struct DefenseSetup
{
    // Tokens
    int dice = 0;
    TokenState tokens;

    // Pilots
	bool rey = false;					// Reroll up to 2 blanks

    // EPTs
    bool wired = false;
    // TODO: Lone wolf (1 blank reroll)
    // TODO: Elusiveness

    // Crew
    bool finn = false;                  // Add one blank result to roll
    // TODO: C-3PO (always guess 0 probably the most relevant)
    // TODO: Latts? Gets a bit weird/complex

    // System upgrades
    bool sensor_jammer = false;         // Change one attacker hit to evade

    // Modifications
    bool autothrusters = false;
    // TODO: Lightweight frame
};


struct SimulationResult
{
    // Performance/debug metadata
    int evaluation_count = 1;

    float probability = 0.0f;

    float hits = 0;
    float crits = 0;

    // After - Before for all values here
    float attack_delta_focus_tokens = 0;
    float attack_delta_target_locks = 0;
    float attack_delta_stress       = 0;

    float defense_delta_focus_tokens = 0;
    float defense_delta_evade_tokens = 0;
    float defense_delta_stress       = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.evaluation_count += b.evaluation_count;
    a.probability += b.probability;

    a.hits += b.hits;
    a.crits += b.crits;

    a.attack_delta_focus_tokens  += b.attack_delta_focus_tokens;
    a.attack_delta_target_locks  += b.attack_delta_target_locks;
    a.attack_delta_stress        += b.attack_delta_stress;

    a.defense_delta_focus_tokens += b.defense_delta_focus_tokens;
    a.defense_delta_evade_tokens += b.defense_delta_evade_tokens;
    a.defense_delta_stress       += b.defense_delta_stress;

    return a;
}

//-----------------------------------------------------------------------------------

// New setup where we only count totals and hash, etc.
struct DiceState
{
    // Count number of dice for each result
    // Count rerolled dice separately (can only reroll each die once)
    int[DieResult.Num] results;
    int[DieResult.Num] rerolled_results;

    // Cancel all dice/reinitialize
    void cancel_all()
    {
        results[] = 0;
        rerolled_results[] = 0;
    }

	// "Simplifies" dice state into only states that matter for comparing results after all modification
	// NOTE: There are a few special cases in which the total number of dice matter (example: lightweight frame)
	// and in those cases it's important that the caller record the necessary metadata before
	// simplifying the dice state.
	void simplify()
	{
		results = count_all();
		rerolled_results[] = 0;
		results[DieResult.Blank] = 0;
		results[DieResult.Focus] = 0;
	}

    // Utilities
    int[DieResult.Num] count_all() const
    {
        int[DieResult.Num] total = results[];
        total[] += rerolled_results[];
        return total;
    }
	int count(DieResult type) const
    {
        return results[type] + rerolled_results[type];
    }
	int count() const	// Count *all* dice
	{
		return sum(count_all()[]);
	}

    // Removes dice that we are able to reroll from results and returns the
    // number that were removed. Caller should add rerolled_results based on this.
    int remove_dice_for_reroll(DieResult from, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        int rerolled_count = min(results[from], max_count);
        results[from] -= rerolled_count;

        return rerolled_count;
    }

    // Prefers changing rerolled dice first where limited as they are more constrained
    int change_dice(DieResult from, DieResult to, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        // Change rerolled dice first
        int changed_count = 0;

        int delta = min(rerolled_results[from], max_count - changed_count);
        if (delta > 0)
        {
            rerolled_results[from] -= delta;
            rerolled_results[to]   += delta;
            changed_count          += delta;
        }
        // Then regular ones
        delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from] -= delta;
            results[to]   += delta;
            changed_count += delta;
        }

        return changed_count;
    }

    // Like above, but the changed dice cannot be rerolled
    // Because this is generally used when modifying *opponents* dice, we prefer
    // to change non-rerolled dice first to add additional constraints.
    // Ex. M9G8 forced reroll and sensor jammer can cause two separate dice
    // to be unable to be rerolled by the attacker.
    int change_dice_no_reroll(DieResult from, DieResult to, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        // Change regular dice first
        int changed_count = 0;

        int delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from]          -= delta;
            rerolled_results[to]   += delta; // Disallow reroll on the changed result(s)
            changed_count          += delta;
        }
        // Then rerolled ones
        delta = min(rerolled_results[from], max_count - changed_count);
        if (delta > 0)
        {
            rerolled_results[from] -= delta;
            rerolled_results[to]   += delta;
            changed_count          += delta;
        }

        return changed_count;
    }
}

//-----------------------------------------------------------------------------------




class Simulation
{
    public this(ref const(AttackSetup)  attack_setup,
                ref const(DefenseSetup) defense_setup)
    {
        m_attack_setup = attack_setup;
        m_defense_setup = defense_setup;

        // We always show at least 0..6 labels on the graph as this looks nice
        m_total_hits_pdf = new SimulationResult[7];
        foreach (ref i; m_total_hits_pdf)
            i = SimulationResult.init;
    }

    // TODO: Needs a way to force rerolls eventually as well
    private void defender_modify_attack_dice(ref DiceState attack_dice,
                                             ref TokenState attack_tokens)
    {
        if (m_defense_setup.sensor_jammer)
            attack_dice.change_dice_no_reroll(DieResult.Hit, DieResult.Focus, 1);
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private int attacker_modify_attack_dice_before_reroll(ref DiceState attack_dice,
                                                          ref TokenState attack_tokens)
    {
        int dice_to_reroll = 0;

        // Add free results
		attack_dice.results[DieResult.Hit]   += m_attack_setup.add_hit_count;
		attack_dice.results[DieResult.Crit]  += m_attack_setup.add_crit_count;
		attack_dice.results[DieResult.Blank] += m_attack_setup.add_blank_count;
		attack_dice.results[DieResult.Focus] += m_attack_setup.add_focus_count;

        // TODO: There are a few effects that should technically change our token spending behavior here...
        // Ex. One Damage on Hit (TLT, Ion) vs. enemies that can only ever get a maximum # of evade results
        // Doing more than that + 1 hits is just wasting tokens, and crits are useless (ex. Calculation)
        // It would be difficult to perfectly model this, and human behavior would not be perfect either.
        // That said, there is probably some low hanging fruit in a few situations that should get us
        // "close enough".

		// TODO: Implement and comprehend the "any_to_hit/crit" stuff here. Gets a bit non-trivial due to
		// free reroll vs. paid reroll logic.

		// "Useful" focus results are ones we can turn into hits or crits
		int useful_focus_results = (m_attack_setup.focus_to_hit_count + m_attack_setup.focus_to_crit_count);
		if (attack_tokens.focus > 0)
			useful_focus_results = int.max;

		// Free rerolls of specific results first
		{
			{
				int focus_to_reroll = min(m_attack_setup.focus_reroll_count, max(0, attack_dice.count(DieResult.Focus) - useful_focus_results));
				dice_to_reroll += attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_to_reroll);
			}

			// Free reroll of any blank results before using our more "general" rerolls
			{
				dice_to_reroll += attack_dice.remove_dice_for_reroll(DieResult.Blank, m_attack_setup.blank_reroll_count);
			}
		}

		// Free general rerolls
		// If we have a target lock, we can reroll everything if we want to
		immutable int total_reroll_count = attack_tokens.target_lock > 0 ? int.max : m_attack_setup.any_reroll_count;
		int any_reroll_count = 0;

		// First, let's reroll any blanks we're allowed to - this is always useful
		any_reroll_count += attack_dice.remove_dice_for_reroll(DieResult.Blank, total_reroll_count);

		// Now reroll focus results that "aren't useful"
		{
			int focus_to_reroll = attack_dice.count(DieResult.Focus) - useful_focus_results;
			focus_to_reroll = clamp(focus_to_reroll, 0, total_reroll_count - any_reroll_count);

			any_reroll_count += attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_to_reroll);
		}

		// If we rerolled more than our total number of "free" rerolls, we have to spend a target lock
		if (any_reroll_count > m_attack_setup.any_reroll_count)
		{
			assert(attack_tokens.target_lock > 0);
			--attack_tokens.target_lock;
		}

        // This is a mess but pending reorg of "free" vs "paid" rerolling logic above
        return dice_to_reroll + any_reroll_count;
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private void attacker_modify_attack_dice_after_reroll(ref DiceState attack_dice,
                                                          ref TokenState attack_tokens)
    {
        // Handle accuracy corrector... we cache the token state here before doing other modification -
        // namely focus spending - because we assume at this point that the player could determine if it's
        // better to spend tokens to modify, or just trigger accuracy corrector.
        // Note that human behavior here is not 100% optimal, but for our purposes it's fair to assume
        // that people will still attempt to modify dice as usual with rerolls until they determine they
        // can't beat AC.
        // TODO: As with some other things there are various edge cases that we could handle here... ex.
        // if there's no possible way to get more than two hits we could just trigger AC right off the bat
        // and ignore the rolled results entirely. More complex, in some cases with FCS + gunner it might be
        // better to cancel but not add the two hits back in to intentionally trigger FCS and gunner for a
        // second attack...
        TokenState attack_tokens_before_ac = attack_tokens;

        // Rerolls are done - change results

		// TODO: Semi-complex logic in the case of abilities where you can spend something to change
        // a finite number of focus or blank results, etc. Gets a bit complicated in the presence of
        // other abilities like marksmanship and expertise and so on.

		// NOTE: Order matters here - do the most useful changes first
		// TODO: There are some cards that do multiple things at once... ex. Marksmanship
		// Ensure that the timing of separating them into multiple effects here is always consistent/correct
		attack_dice.change_dice(DieResult.Blank, DieResult.Crit, m_attack_setup.blank_to_crit_count);
		attack_dice.change_dice(DieResult.Blank, DieResult.Hit,  m_attack_setup.blank_to_hit_count);
		attack_dice.change_dice(DieResult.Focus, DieResult.Crit, m_attack_setup.focus_to_crit_count);
		attack_dice.change_dice(DieResult.Focus, DieResult.Hit,  m_attack_setup.focus_to_hit_count);

        // Spend regular focus?
        if (attack_tokens.focus > 0)
        {
            int changed_results = attack_dice.change_dice(DieResult.Focus, DieResult.Hit);
            if (changed_results > 0)
                --attack_tokens.focus;
        }

		// Modify any hit results (including those generated above) as appropriate
		attack_dice.change_dice(DieResult.Hit, DieResult.Crit, m_attack_setup.hit_to_crit_count);

        // Use accuracy corrector in the following cases:
        // a) We ended up with less than 2 hits/crits
        // b) We got exactly 2 hits/crits but we only care if we "hit the attack" (TLT, Ion, etc)
        // b) We got exactly 2 hits and no crits (still better to remove the extra die for LWF, and not spend tokens)
        if (m_attack_setup.accuracy_corrector)
        {
            int hits = attack_dice.count(DieResult.Hit);
            int crits = attack_dice.count(DieResult.Crit);
            if (((hits + crits) <  2) ||
                (hits == 2 && crits == 0) ||
                ((hits + crits) == 2 && m_attack_setup.one_damage_on_hit))
            {
                attack_tokens = attack_tokens_before_ac;  // Undo focus token spending (see above notes)

                attack_dice.cancel_all();
                attack_dice.results[DieResult.Hit] += 2;
            }
        }
        // No more modification after AC!
    }

    void attacker_modify_defense_dice(const(int)[DieResult.Num] attack_results,
                                      ref DiceState defense_dice,
                                      ref TokenState defense_tokens)
    {
        // Find one evade and turn it to a focus
        if (m_attack_setup.juke)
            defense_dice.change_dice(DieResult.Evade, DieResult.Focus, 1);
    }

    int defender_modify_defense_dice_before_reroll(const(int)[DieResult.Num] attack_results,
                                                   ref DiceState defense_dice,
                                                   ref TokenState defense_tokens)
    {
        int dice_to_reroll = 0;

        // Add free results
        if (m_defense_setup.finn)
            ++defense_dice.results[DieResult.Blank];

		// Reroll any blanks that we can (always useful)
		if (m_defense_setup.rey)
		{
			dice_to_reroll += defense_dice.remove_dice_for_reroll(DieResult.Blank, 2);
		}

        // If we have any focus results and no focus token, reroll our focuses
        if (defense_tokens.focus == 0 && m_defense_setup.wired)
        {
            dice_to_reroll += defense_dice.remove_dice_for_reroll(DieResult.Focus);
        }

        return dice_to_reroll;
    }

    void defender_modify_defense_dice_after_reroll(const(int)[DieResult.Num] attack_results,
                                                   ref DiceState defense_dice,
                                                   ref TokenState defense_tokens)
    {
		// Find one blank and turn it to an evade
        if (m_defense_setup.autothrusters)
            defense_dice.change_dice(DieResult.Blank, DieResult.Evade, 1);

        int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit] - defense_dice.count(DieResult.Evade);
		int focus_results = defense_dice.count(DieResult.Focus);

		// FAQ update: can only spend a single focus or evade per attack!
        bool can_spend_focus = defense_tokens.focus > 0 && focus_results > 0;		
		bool can_spend_evade = (defense_tokens.evade > 0);

        // Spend regular focus or evade tokens?
        if (uncanceled_hits > 0 && (can_spend_focus || can_spend_evade))
        {
            int max_damage_canceled = (can_spend_focus ? focus_results : 0) + (can_spend_evade ? 1 : 0);
            bool can_cancel_all = (max_damage_canceled >= uncanceled_hits);

            // In the presence of "one damage on hit" effects from the attacker, if we can't cancel everything,
            // it's pointless to spend any tokens at all.
            if (can_cancel_all || !m_attack_setup.one_damage_on_hit)
            {
                // For now simple logic:
                // Cancel all hits with just a focus? Do it.
                // Cancel all hits with just evade tokens? Do that.
                // If attacker has juke, flip this order - it's usually better to hang on to focus tokens vs. juke
                //   NOTE: Optimal strategy here depends on quite a lot of factors, but this is good enough in most cases
                // Otherwise both.

                bool can_cancel_all_with_focus = can_spend_focus && (focus_results >= uncanceled_hits);
                bool can_cancel_all_with_evade = can_spend_evade && (1 >= uncanceled_hits);

                bool spent_focus = false;
                bool spent_evade = false;

                // Do we need to spend both to cancel all hits?
                if (!can_cancel_all_with_focus && !can_cancel_all_with_evade)
                {
                    spent_focus = can_spend_focus;
					spent_evade = can_spend_evade;
                }
                else if (!m_attack_setup.juke)      // No juke - hold onto evade primarily
                {
                    if (can_cancel_all_with_focus)
                        spent_focus = can_spend_focus;
                    else
					{
						assert(can_cancel_all_with_evade);
                        spent_evade = can_spend_evade;
					}
                }
                else                                // Juke - hold on to focus primarily
                {
                    if (can_cancel_all_with_evade)
                        spent_evade = can_spend_evade;
                    else
					{
						assert(can_cancel_all_with_focus);
                        spent_focus = can_spend_focus;
					}
                }

                if (spent_focus)
                {
                    uncanceled_hits -= focus_results;
                    defense_dice.change_dice(DieResult.Focus, DieResult.Evade);
                    --defense_tokens.focus;
                }

                // Evade tokens add defense dice to the pool
                if (spent_evade)
                {
                    --uncanceled_hits;
                    ++defense_dice.results[DieResult.Evade];
                    --defense_tokens.evade;
                }

                assert(uncanceled_hits <= 0 || ((!can_spend_focus || spent_focus) && (!can_spend_evade || spent_evade)));
            }

            // Sanity
            assert(defense_tokens.evade >= 0);
            assert(defense_tokens.focus >= 0);
            assert(uncanceled_hits <= 0 || !can_cancel_all);
        }
    }

    private int[DieResult.Num] compare_results(int[DieResult.Num] attack_results,
                                               int[DieResult.Num] defense_results)
    {
        // Sanity...
        assert(attack_results[DieResult.Evade] == 0);
        assert(defense_results[DieResult.Hit] == 0);
        assert(defense_results[DieResult.Crit] == 0);

        // Compare results

        // Cancel pairs of hits and evades
        {
            int canceled_hits = min(attack_results[DieResult.Hit], defense_results[DieResult.Evade]);
            attack_results[DieResult.Hit]    -= canceled_hits;
            defense_results[DieResult.Evade] -= canceled_hits;

            // Cancel pairs of crits and evades
            int canceled_crits = min(attack_results[DieResult.Crit], defense_results[DieResult.Evade]);
            attack_results[DieResult.Crit]   -= canceled_crits;
            defense_results[DieResult.Evade] -= canceled_crits;
        }

        bool attack_hit = (attack_results[DieResult.Hit] + attack_results[DieResult.Crit]) > 0;

        // TLT/ion does one damage if it hits, regardless of the dice results
        if (m_attack_setup.one_damage_on_hit && attack_hit)
        {
            attack_results[DieResult.Hit] = 1;
            attack_results[DieResult.Crit] = 0;
        }
        return attack_results;
    }

    private void after_attack(ref TokenState attack_tokens, ref TokenState defense_tokens)
    {
        // Update any abilities that trigger "after attacking" or "after defending"
        if (m_attack_setup.fire_control_system)
        {
            // TODO: Handle multi-target-lock stuff... really only an issue with Redline and so on
            attack_tokens.target_lock = max(attack_tokens.target_lock, 1);
        }
    }


    //************************************** EXHAUSTIVE SEARCH *****************************************
    // TODO: Can generalize this but okay for now
    // Do it in float since for our purposes we always end up converting immediately anyways
    static immutable int[] k_factorials_table = [
        1,                  // 0!
        1,                  // 1!
        2,                  // 2!
        6,                  // 3!
        24,                 // 4!
        120,                // 5!
        720,                // 6!
        5040,               // 7!
        40320,              // 8!
        362880,             // 9!
        3628800,            // 10!
    ];
    static int factorial(int n)
    {
        assert(n < k_factorials_table.length);
        return k_factorials_table[n];
    }

    struct ExhaustiveState
    {
        DiceState attack_dice;
        TokenState attack_tokens;
        DiceState defense_dice;
        TokenState defense_tokens;

		// Information for next stage of iteration
		int dice_to_reroll = 0;

		// Final results (multi-attack, etc)
		int completed_attack_count = 0;
		int final_hits = 0;
		int final_crits = 0;

		// TODO: Since this is such an important part of the simulation process now, we should compress
		// the size of this structure and implement (and test!) a proper custom hash function.
    }

	// Maps state -> probability
	alias ExhaustiveStateMap = float[ExhaustiveState];
	ExhaustiveStateMap m_prev_state;
	ExhaustiveStateMap m_next_state;

    alias ForkDiceDelegate = ExhaustiveState delegate(ExhaustiveState state);

	// Utility to either insert a new state into the map, or accumualte probability if already present
	void append_state(ref ExhaustiveStateMap map, ExhaustiveState state, float probability)
	{
		auto i = (state in map);
		if (i)
		{
			//writefln("Append state: %s", state);
			*i += probability;
		}
		else
		{
			//writefln("New state: %s", state);
			map[state] = probability;
		}
	}

	// Take all previous states, roll state.dice_roll attack dice, call "cb" delegate on each of them,
	// accumulate into new states depending on uniqueness of the key and return the new map.
	// TODO: Probably makes sense to have a cleaner division between initial roll and rerolls at this point
	// considering it complicates the calling code a bit too (having to put things into state.dice_to_roll)
    ExhaustiveStateMap exhaustive_roll_attack_dice(bool initial_roll)(ExhaustiveStateMap prev_states,
																	  ForkDiceDelegate cb,
																	  int initial_roll_dice = 0)
    {
		ExhaustiveStateMap next_states;
		foreach (state, state_probability; prev_states)
		{
			int count = initial_roll ? initial_roll_dice : state.dice_to_reroll;

			// TODO: Could probably clean this up a bit but what it does is fairly clear
			float total_fork_probability = 0.0f;            // Just for debug
			for (int crit = 0; crit <= count; ++crit)
			{
				for (int hit = 0; hit <= (count - crit); ++hit)
				{
					for (int focus = 0; focus <= (count - crit - hit); ++focus)
					{
						int blank = count - crit - hit - focus;
						assert(blank >= 0);

						// Add dice to the relevant pool
						ExhaustiveState new_state = state;
						new_state.dice_to_reroll = 0;
						if (initial_roll)
						{
							new_state.attack_dice.results[DieResult.Crit]  += crit;
							new_state.attack_dice.results[DieResult.Hit]   += hit;
							new_state.attack_dice.results[DieResult.Focus] += focus;
							new_state.attack_dice.results[DieResult.Blank] += blank;
						}
						else
						{
							new_state.attack_dice.rerolled_results[DieResult.Crit]  += crit;
							new_state.attack_dice.rerolled_results[DieResult.Hit]   += hit;
							new_state.attack_dice.rerolled_results[DieResult.Focus] += focus;
							new_state.attack_dice.rerolled_results[DieResult.Blank] += blank;
						}

						// Work out probability of this configuration and accumulate                    
						// Multinomial distribution: https://en.wikipedia.org/wiki/Multinomial_distribution
						// n = count
						// k = 4 (possible outcomes)
						// p_1 = P(blank) = 2/8; x_1 = blank
						// p_2 = P(focus) = 2/8; x_2 = focus
						// p_3 = P(hit)   = 3/8; x_3 = hit
						// p_4 = P(crit)  = 1/8; x_4 = crit
						// n! / (x_1! * ... * x_k!) * p_1^x_1 * ... p_k^x_k

						// Could also do this part in integers/fixed point easily enough actually... revisit
						// TODO: Optimize for small integer powers if needed
						float nf = cast(float)factorial(count);
						float xf = cast(float)(factorial(blank) * factorial(focus) * factorial(hit) * factorial(crit));
						float p = pow(0.25f, blank + focus) * pow(0.375f, hit) * pow(0.125f, crit);

						float roll_probability = (nf / xf) * p;
						assert(roll_probability >= 0.0f && roll_probability <= 1.0f);
						total_fork_probability += roll_probability;
						assert(total_fork_probability >= 0.0f && total_fork_probability <= 1.0f);

						float next_state_probability = roll_probability * state_probability;
						append_state(next_states, cb(new_state), next_state_probability);
					}
				}
			}

			// Total probability of our fork loop should be very close to 1, modulo numeric precision
			assert(abs(total_fork_probability - 1.0f) < 1e-6f);
		}

		//writefln("After %s attack states: %s", initial_roll ? "initial" : "reroll", next_states.length);
		return next_states;
    }

    ExhaustiveStateMap exhaustive_roll_defense_dice(bool initial_roll)(ExhaustiveStateMap prev_states,
																	   ForkDiceDelegate cb, 
																	   int initial_roll_dice = 0)
    {
        float total_fork_probability = 0.0f;            // Just for debug

		ExhaustiveStateMap next_states;
		foreach (state, state_probability; prev_states)
		{
			int count = initial_roll ? initial_roll_dice : state.dice_to_reroll;

			// TODO: Could probably clean this up a bit but what it does is fairly clear
			float total_fork_probability = 0.0f;            // Just for debug
			for (int evade = 0; evade <= count; ++evade)
			{
				for (int focus = 0; focus <= (count - evade); ++focus)
				{
					int blank = count - focus - evade;
					assert(blank >= 0);

					// Add dice to the relevant pool
					ExhaustiveState new_state = state;
					new_state.dice_to_reroll = 0;
					if (initial_roll)
					{
						new_state.defense_dice.results[DieResult.Evade] += evade;
						new_state.defense_dice.results[DieResult.Focus] += focus;
						new_state.defense_dice.results[DieResult.Blank] += blank;
					}
					else
					{
						new_state.defense_dice.rerolled_results[DieResult.Evade] += evade;
						new_state.defense_dice.rerolled_results[DieResult.Focus] += focus;
						new_state.defense_dice.rerolled_results[DieResult.Blank] += blank;
					}                

					// Work out probability of this configuration and accumulate (see attack dice)
					// P(blank) = 3/8
					// P(focus) = 2/8
					// P(evade) = 3/8
					float nf = cast(float)factorial(count);
					float xf = cast(float)(factorial(blank) * factorial(focus) * factorial(evade));
					float p = pow(0.375f, blank + evade) * pow(0.25f, focus);

					float roll_probability = (nf / xf) * p;
					assert(roll_probability >= 0.0f && roll_probability <= 1.0f);
					total_fork_probability += roll_probability;
					assert(total_fork_probability >= 0.0f && total_fork_probability <= 1.0f);

					float next_state_probability = roll_probability * state_probability;
					append_state(next_states, cb(new_state), next_state_probability);
				}
			}

			// Total probability of our fork loop should be very close to 1, modulo numeric precision
			assert(abs(total_fork_probability - 1.0f) < 1e-6f);
		}
        
		//writefln("After %s defense states: %s", initial_roll ? "initial" : "reroll", next_states.length);
		return next_states;
    }

	// Returns full set of states after result comparison (results put into state.final_hits, etc)
	// Does not directly accumulate as this may be part of a multi-attack sequence.
	public ExhaustiveStateMap simulate_single_attack_exhaustive(TokenState attack_tokens,
																TokenState defense_tokens)
	{
		ExhaustiveState initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;

		ExhaustiveStateMap states;
		states[initial_state] = 1.0f;

		// TODO: first optimize the state set into the things that matter for this attack: tokens
		// We can't completely drop the rest of state because it matters in the composite results - i.e. we have to
		// accumulate the "final" results appropriately with the states they came from still.
		// This does require keeping a map from input token state -> [all output states] and then composing the
		// two for each input state after simulation.

		// Roll and modify attack dice
		states = exhaustive_roll_attack_dice!(true)(states, &exhaustive_attack_modify_before_reroll, m_attack_setup.dice);
		states = exhaustive_roll_attack_dice!(false)(states, &exhaustive_attack_modify_after_reroll);

		// Roll and modify defense dice, and compare results
        states = exhaustive_roll_defense_dice!(true)(states, &exhaustive_defense_modify_before_reroll, m_defense_setup.dice);
		states = exhaustive_roll_defense_dice!(false)(states, &exhaustive_defense_modify_after_reroll);

		return states;
	}


	// Returns full set of states after result comparison (results put into state.final_hits, etc)
	// Does not directly accumulate as this may be part of a multi-attack sequence.
	public ExhaustiveStateMap simulate_single_attack_exhaustive(ExhaustiveStateMap initial_states)
	{
		// NOTE: It would be "correct" here to just immediately fork all of our states set into another attack,
		// but that is relatively inefficient. Since the core thing that affects how the next attack plays out is
		// our *tokens*, we want to only simulate additional attacks with unique token sets, then apply
		// the results to any input states with that token set.

		// For now we'll do that in the simplest way possible: simply iterate the states and perform second
		// attack simulations for any unique token sets that we run into. Then we'll apply the results with all
		// input states to use that token set.
		//
		// NOTE: This is all assuming that an "attack" logic only depends on the "setup" and "tokens", and never
		// on anything like the number of hits that happened in the previous attack. This is a safe assumption for
		// now. We could technically split our state set into two parts to represent this more formally, but that
		// would make it a lot more wordy - and potentially less efficient - to pass it around everywhere.
		//
		// TODO: Lots of this can be optimized, but it culls so much work compared to the brute force thing that
		// it's already really "fast enough" to be honest.

		ExhaustiveStateMap new_states;
		while (initial_states.length > 0)
		{
			// Simulate an attack with the tokens from the first state
			TokenState attack_tokens = initial_states.keys[0].attack_tokens;
			TokenState defense_tokens = initial_states.keys[0].defense_tokens;

			auto second_attack_states = simulate_single_attack_exhaustive(attack_tokens, defense_tokens);

			// Now find all attacks in our initial state list that ended with the same tokens
			// Since it's illegal to delete elements from the AA as we go, we'll add ones that we didn't delete to
			// a separate AA instead...
			ExhaustiveStateMap kept_states;
			foreach (ref initial_state, initial_probability; initial_states)
			{
				if (initial_state.attack_tokens == attack_tokens && initial_state.defense_tokens == defense_tokens)
				{
					// Compose all of the results from the second attack set with this one
					foreach (ref second_attack_state, second_probability; second_attack_states)
					{
						// NOTE: Important to keep the token state and such from after the second attack, not initial one
						// We basically just want to add each of the combinations of "final hits/crits" together for the
						// combined attack.
						ExhaustiveState new_state = second_attack_state;
						new_state.final_hits			 += initial_state.final_hits;
						new_state.final_crits		     += initial_state.final_crits;
						new_state.completed_attack_count += initial_state.completed_attack_count;
						append_state(new_states, new_state, initial_probability * second_probability);
					}
				}
				else
				{
					kept_states[initial_state] = initial_probability;
				}
			}

			// Should always consume at least the one input we had...
			assert(kept_states.length < initial_states.length);
			initial_states = kept_states;
		}

		return new_states;
	}

    public void simulate_attack_exhaustive()
    {		
		// First attack
		auto states = simulate_single_attack_exhaustive(m_attack_setup.tokens, m_defense_setup.tokens);

		//writefln("Attack complete with %s states.", states.length);

		if (m_attack_setup.type == MultiAttackType.SecondaryPerformTwice ||
			m_attack_setup.type == MultiAttackType.AfterAttack)
		{
			// Unconditional second attacks
			states = simulate_single_attack_exhaustive(states);
		}
		else if (m_attack_setup.type == MultiAttackType.AfterAttackDoesNotHit)
		{
			// Only attack again for the states that didn't hit anything
			ExhaustiveStateMap second_attack_states;
			ExhaustiveStateMap no_second_attack_states;
			foreach (ref state, state_probability; states)
			{
				if (state.final_hits == 0 && state.final_crits == 0)
				{
					second_attack_states[state] = state_probability;
				}
				else
				{
					no_second_attack_states[state] = state_probability;
				}
			}

			//writefln("Second attack for %s states.", second_attack_states.length);

			// Do the next attack for those states, then merge them into the other list
			second_attack_states = simulate_single_attack_exhaustive(second_attack_states);

			states = no_second_attack_states;
			foreach (ref state, state_probability; second_attack_states)
			{
				assert(!(state in states));		// Should not be possible since attack index will be incremented
				states[state] = state_probability;
			}
		}

		// Record final results
		foreach (ref state, state_probability; states)
		{
			accumulate(state_probability, state.final_hits, state.final_crits, state.attack_tokens, state.defense_tokens);
		}
    }

    private ExhaustiveState exhaustive_attack_modify_before_reroll(ExhaustiveState state)
    {
        // "After rolling" events
        if (m_attack_setup.heavy_laser_cannon)
            state.attack_dice.change_dice(DieResult.Crit, DieResult.Hit);

        defender_modify_attack_dice(state.attack_dice, state.attack_tokens);
        state.dice_to_reroll = attacker_modify_attack_dice_before_reroll(state.attack_dice, state.attack_tokens);
		return state;
	}

    private ExhaustiveState exhaustive_attack_modify_after_reroll(ExhaustiveState state)
    {
        attacker_modify_attack_dice_after_reroll(state.attack_dice, state.attack_tokens);		
        // Done modifying attack dice

		// State simplification
		// TODO: Store total dice count somewhere if lightweight frame or other effects are present for defender
		state.dice_to_reroll = 0;
		state.attack_dice.simplify();

		return state;
    }

    private ExhaustiveState exhaustive_defense_modify_before_reroll(ExhaustiveState state)
    {
        attacker_modify_defense_dice(state.attack_dice.count_all(), state.defense_dice, state.defense_tokens);
        state.dice_to_reroll = defender_modify_defense_dice_before_reroll(state.attack_dice.count_all(), state.defense_dice, state.defense_tokens);
		return state;
    }

    private ExhaustiveState exhaustive_defense_modify_after_reroll(ExhaustiveState state)
    {
        defender_modify_defense_dice_after_reroll(state.attack_dice.count_all(), state.defense_dice, state.defense_tokens);
        // Done modifying defense dice

		// Compare results
		auto attack_results = compare_results(state.attack_dice.count_all(), state.defense_dice.count_all());

		// "After attack" abilities do not trigger on the first of a "secondary perform twice" attack
		if (state.completed_attack_count > 0 || m_attack_setup.type != MultiAttackType.SecondaryPerformTwice)
		{
			after_attack(state.attack_tokens, state.defense_tokens);
		}

		state.final_hits  += attack_results[DieResult.Hit];
		state.final_crits += attack_results[DieResult.Crit];
		++state.completed_attack_count;

		// Simplify state in case of further iteration
		// Keep tokens and final results, discard the rest
		state.dice_to_reroll = 0;
		state.attack_dice.cancel_all();
		state.defense_dice.cancel_all();

		// TODO: Maybe assert only the relevant states are set on output here

		return state;
    }

    






    private void accumulate(float probability, int hits, int crits, TokenState attack_tokens, TokenState defense_tokens)
    {
        // Sanity checks on token spending
        assert(attack_tokens.focus >= 0);
        assert(attack_tokens.evade >= 0);
        assert(attack_tokens.target_lock >= 0);
        assert(attack_tokens.stress >= 0);

        assert(defense_tokens.focus >= 0);
        assert(defense_tokens.evade >= 0);
        assert(defense_tokens.target_lock >= 0);
        assert(defense_tokens.stress >= 0);

        // Compute final results of this simulation step
        // TODO: Can clean this up
        SimulationResult result;
        result.probability = probability;

        result.hits  = probability * cast(float)hits;
        result.crits = probability * cast(float)crits;

        result.attack_delta_focus_tokens  = probability * cast(float)(attack_tokens.focus        - m_attack_setup.tokens.focus      );
        result.attack_delta_target_locks  = probability * cast(float)(attack_tokens.target_lock  - m_attack_setup.tokens.target_lock);
        result.attack_delta_stress        = probability * cast(float)(attack_tokens.stress       - m_attack_setup.tokens.stress     );
        result.defense_delta_focus_tokens = probability * cast(float)(defense_tokens.focus       - m_defense_setup.tokens.focus     );
        result.defense_delta_evade_tokens = probability * cast(float)(defense_tokens.evade       - m_defense_setup.tokens.evade     );
        result.defense_delta_stress       = probability * cast(float)(defense_tokens.stress      - m_defense_setup.tokens.stress    );

        m_total_sum = accumulate_result(m_total_sum, result);

        // Accumulate into the right bin of the total hits PDF
        int total_hits = hits + crits;
        if (total_hits >= m_total_hits_pdf.length)
            m_total_hits_pdf.length = total_hits + 1;
        m_total_hits_pdf[total_hits] = accumulate_result(m_total_hits_pdf[total_hits], result);
    }

    public SimulationResult[] total_hits_pdf() const
    {
        return m_total_hits_pdf.dup;
    }

    public SimulationResult total_sum() const
    {
        return m_total_sum;
    }

    // Accumulated results
    private SimulationResult[] m_total_hits_pdf;
    private SimulationResult m_total_sum;

    private immutable AttackSetup m_attack_setup;
    private immutable DefenseSetup m_defense_setup;
};

