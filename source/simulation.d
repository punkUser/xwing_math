module simulation;

import std.algorithm;
import std.random;
import std.stdio;

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

struct AttackDie
{
    public  DieResult result = DieResult.Num;
    private int roll_count = 0;

    public this(DieResult r)
    {
        result = r;
        roll_count = 1;
    }
    public void roll()
    {
        assert(can_reroll());
        result = k_attack_die_result[uniform(0, k_die_sides)];
        ++roll_count;
    }
    public bool can_reroll() const { return roll_count < 2; }

    // Convenience
    public @property bool blank() const { return result == DieResult.Blank; }
    public @property bool focus() const { return result == DieResult.Focus; }
    public @property bool hit() const   { return result == DieResult.Hit; }
    public @property bool crit() const   { return result == DieResult.Crit; }
};

struct DefenseDie
{
    public  DieResult result = DieResult.Num;
    private int roll_count = 0;

    public this(DieResult r)
    {
        result = r;
        roll_count = 1;
    }
    public void roll()
    {
        assert(can_reroll());
        result = k_defense_die_result[uniform(0, k_die_sides)];
        ++roll_count;
    }
    public bool can_reroll() const { return roll_count < 2; }

    // Convenience
    public @property bool blank() const { return result == DieResult.Blank; }
    public @property bool focus() const { return result == DieResult.Focus; }
    public @property bool evade() const { return result == DieResult.Evade; }
};

int[DieResult.Num] count_results(T)(const(T)[] dice)
{
    int[DieResult.Num] results;
    foreach (d; dice)
        ++results[d.result];
    return results;
}

// max_count < 0 means no maximum
// Returns number of dice changed
int change_dice(T)(ref T[] dice, DieResult from, DieResult to, int max_count = -1)
{
    if (max_count == 0)
        return 0;
    else if (max_count < 0)
        max_count = cast(int)dice.length;

    int changed_count = 0;
    foreach (ref d; dice)
    {
        if (d.result == from)
        {
            d.result = to;
            ++changed_count;
            if (changed_count >= max_count)
                break;
        }
    }
    return changed_count;
}

enum MultiAttackType : int
{
    Single = 0,                   // Regular single attack
    SecondaryPerformTwice,        // Ex. Twin Laser Turret, Cluster Missiles
    AfterAttackDoesNotHit,        // Ex. Gunner, Luke, IG88-B - TODO: Luke Gunner modeling somehow?
    AfterAttack,                  // Ex. Corran    
};

// TODO: Optimize the bools into a bitfield since this structure does got copied/passed by value a few times
// Alternatively, maybe just separate out the tokens into a separate structure, since the other stuff is
// read-only.

struct AttackSetup
{
    MultiAttackType type = MultiAttackType.Single;

    // Tokens
    int dice = 0;
    int focus_token_count = 0;
    int target_lock_count = 0;
    int stress_token_count = 0;

    // Pilots

    // EPT
    bool juke = false;                  // Setting this to true implies evade token present as well
    bool marksmanship = false;          // One focus->crit, rest focus->hit
    int  predator_rerolls = 0;          // 0-2 rerolls
    bool rage = false;                  // 3 rerolls
    bool wired = false;                 // reroll any/all focus
    bool expertise = false;             // all focus -> hits    
    bool fearlessness = false;          // add 1 hit result
    // TODO: Lone wolf (1 blank reroll)
    // TODO: Crack shot? (gets a little bit complex as presence affects defender logic and as well)

    // Crew
    bool mercenary_copilot = false;     // One hit->crit
    // TODO: Ezra Crew (one focus->crit)
    // TODO: Zuckuss Crew
    // TODO: 4-LOM Crew
    // TODO: Dengar Crew
    // TODO: Bossk Crew (gets weird/hard...)

    // System upgrades
    bool accuracy_corrector = false;    // Can cancel all results and replace with 2 hits    
    bool fire_control_system = false;   // Get a target lock after attack (only affects multi-attack)
    
    // Secondary weapons
    bool heavy_laser_cannon = false;    // After initial roll, change all crits->hits
    bool mangler_cannon = false;        // One hit->crit
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
    int initial_focus_token_count = 0;
    int initial_evade_token_count = 0;
    int initial_stress_token_count = 0;

    // Pilots

    // EPTs
    bool wired = false;
    // TODO: Lone wolf (1 blank reroll)
    // TODO: Elusiveness

    // Crew
    // TODO: C-3PO (always guess 0 probably the most relevant)
    // TODO: Latts? Gets a bit weird/complex

    // Modifications
    bool autothrusters = false;
    // TODO: Lightweight frame
};

struct SimulationResult
{
    int trial_count = 0;

    int hits = 0;
    int crits = 0;

    // After - Before for all values here
    int attack_delta_focus_tokens = 0;
    int attack_delta_target_locks = 0;
    int attack_delta_stress       = 0;

    int defense_delta_focus_tokens = 0;
    int defense_delta_evade_tokens = 0;
    int defense_delta_stress       = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.trial_count += b.trial_count;

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

struct TokenState
{
    int focus = 0;
    int evade = 0;
    int target_lock = 0;
    int stress = 0;
}


// New setup where we only count totals and hash, etc.
struct DiceState
{
    // Count number of dice for each result
    // Count rerolled dice separately (can only reroll each die once)
    int[DieResult.Num] results;
    int[DieResult.Num] rerolled_results;

    // Utilities
    int count(DieResult type) const
    {
        return results[type] + rerolled_results[type];
    }
    int[DieResult.Num] count_all() const
    {
        int[DieResult.Num] total = results[];
        total[] += rerolled_results[];
        return total;
    }

    // Rolling
    void add_random_attack_die()
    {
        auto result = k_attack_die_result[uniform(0, k_die_sides)];
        ++results[result];
    }
    void add_random_defense_die()
    {
        auto result = k_defense_die_result[uniform(0, k_die_sides)];
        ++results[result];
    }

    int reroll_defense_dice(DieResult from, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        int rerolled_count = min(results[from], max_count);
        results[from] -= rerolled_count;
        
        foreach (i; 0 .. rerolled_count)
        {
            auto new_result = k_defense_die_result[uniform(0, k_die_sides)];
            ++rerolled_results[new_result];
        }

        return rerolled_count;
    }

    // Prefers changing rerolled dice first where limited as they are more constrained
    // I don't think there are currently any cases where this matters though
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
}








void defender_modify_attack_dice(ref AttackSetup  attack_setup,
                                 ref const(DefenseSetup) defense_setup,
                                 ref AttackDie[] attack_dice)
{
}

void attacker_modify_attack_dice(ref AttackSetup  attack_setup,
                                 ref const(DefenseSetup) defense_setup,
                                 ref AttackDie[] attack_dice)
{
    // Add any free results
    // TODO: Probably better to figure out a way to do this without allocation
    if (attack_setup.fearlessness)
        attack_dice ~= AttackDie(DieResult.Hit);

    auto dice_results = count_results(attack_dice);

    // TODO: There are a few effects that should technically change our token spending behavior here...
    // Ex. One Damage on Hit (TLT, Ion) vs. enemies that can only ever get a maximum # of evade results
    // Doing more than that + 1 hits is just wasting tokens, and crits are useless (ex. Calculation)
    // It would be difficult to perfectly model this, and human behavior would not be perfect either.
    // That said, there is probably some low hanging fruit in a few situations that should get us
    // "close enough".

    // Compute attack setup metadata
    int attack_dice_count = cast(int)attack_dice.length;

    // How many focus results can we turn into hits or crits?
    int useful_focus_results = 0;
    if (dice_results[DieResult.Focus] > 0)   // Just an early out
    {
        // All of them
        if (attack_setup.focus_token_count > 0 || attack_setup.marksmanship || attack_setup.expertise)
            useful_focus_results = dice_results[DieResult.Focus];

        // TODO: Other effects as we add them (Ezra, etc.)

        // If we are able to free reroll any focus results (wired, etc) that aren't useful, do so now
        if (attack_setup.wired)
        {
            int focus_to_reroll = dice_results[DieResult.Focus] - useful_focus_results;
            for (int i = 0; i < attack_dice_count && focus_to_reroll > 0; ++i)
            {
                if (attack_dice[i].can_reroll() && attack_dice[i].focus)
                {
                    attack_dice[i].roll();
                    --focus_to_reroll;
                }
            }

            // Recount after rerolling (could update as we go, but this is simpler)
            dice_results = count_results(attack_dice);
        }
    }

    // TODO: Any effects that modify blank dice into something useful here

    // How many free, unrestricted rerolls do we have?
    int free_reroll_count = 0;
    free_reroll_count += attack_setup.predator_rerolls;
    free_reroll_count += attack_setup.rage ? 3 : 0;

    // If we have a target lock, we can reroll everything if we want to
    int total_reroll_count = attack_setup.target_lock_count > 0 ? attack_dice_count : free_reroll_count;

    // First, let's reroll any blanks we're allowed to - this is always useful
    int rerolled_dice_count = 0;
    for (int i = 0; i < attack_dice_count && rerolled_dice_count < total_reroll_count; ++i)
    {
        if (attack_dice[i].can_reroll() && attack_dice[i].blank)
        {
            attack_dice[i].roll();
            ++rerolled_dice_count;
        }
    }

    // Now reroll focus results that "aren't useful"
    // Because not all dice can be rerolled (due to earlier rerolls), we need to eagerly reroll any that
    // we are allowed to, so rely on the math here.
    {
        int focus_to_reroll = dice_results[DieResult.Focus] - useful_focus_results;
        for (int i = 0; i < attack_dice_count && focus_to_reroll > 0 && rerolled_dice_count < total_reroll_count; ++i)
        {
            if (attack_dice[i].can_reroll() && attack_dice[i].focus)
            {
                attack_dice[i].roll();
                --focus_to_reroll;
                ++rerolled_dice_count;
            }
        }
    }

    // If we rerolled more than our total number of "free" rerolls, we have to spend a target lock
    if (rerolled_dice_count > free_reroll_count)
    {
        assert(attack_setup.target_lock_count > 0);
        --attack_setup.target_lock_count;
    }

    // Rerolls are done - deal with focus results

    // TODO: Semi-complex logic in the case of abilities where you can spend something to change
    // a finite number of focus or blank results, etc. Gets a bit complicated in the presence of
    // other abilities like marksmanship and expertise and so on.

    // Marksmanship is always a better choice than regular focus token
    if (attack_setup.marksmanship)
    {
        change_dice(attack_dice, DieResult.Focus, DieResult.Crit, 1);
        change_dice(attack_dice, DieResult.Focus, DieResult.Hit);
    }
    // Expertise is the same as a regular focus token, but doesn't cost anything
    else if (attack_setup.expertise)
    {
        change_dice(attack_dice, DieResult.Focus, DieResult.Hit);
    }
    // Spend regular focus?
    else if (attack_setup.focus_token_count > 0)
    {
        int changed_results = change_dice(attack_dice, DieResult.Focus, DieResult.Hit);
        if (changed_results > 0)
            --attack_setup.focus_token_count;
    }

    // Mangler and merc copilot can make a hit into a crit
    // Do this last in case we focused into any hits, etc.
    {
        int hits_to_crits =
            (attack_setup.mercenary_copilot ? 1 : 0) +
            (attack_setup.mangler_cannon    ? 1 : 0);
        if (hits_to_crits > 0)
            change_dice(attack_dice, DieResult.Hit, DieResult.Crit, hits_to_crits);
    }


    // Some final sanity checks in debug mode on the logic here as it is not always trivial...
    debug
    {
        // Did we have the ability to reroll more dice than we did?
        if (total_reroll_count > rerolled_dice_count)
        {
            // If so, every focus or blank result that is still around here should have been rerolled
            foreach (d; attack_dice)
            {
                if (d.can_reroll() && (d.blank || d.focus))
                    assert(false);
            }
        }
    }


    // TODO: Accuracy corrector should technically go here as it is part of the attacker modify dice section
}

int[DieResult.Num] roll_and_modify_attack_dice(ref AttackSetup  attack_setup,
                                               ref const(DefenseSetup) defense_setup)
{
    AttackSetup initial_attack_setup = attack_setup;

    // Roll Attack Dice
    auto attack_dice = new AttackDie[attack_setup.dice];
    foreach (ref d; attack_dice)
        d.roll();

    // "Immediately after rolling" events
    if (attack_setup.heavy_laser_cannon)
        change_dice(attack_dice, DieResult.Crit, DieResult.Hit);

    defender_modify_attack_dice(attack_setup, defense_setup, attack_dice);
    attacker_modify_attack_dice(attack_setup, defense_setup, attack_dice);

    // Done modifying attack dice - compute attack results
    auto attack_results = count_results(attack_dice);

    // Use accuracy corrector in the following cases:
    // a) We ended up with less than 2 hits/crits
    // b) We got exactly 2 hits/crits but we only care if we "hit the attack" (TLT, Ion, etc)
    // b) We got exactly 2 hits and no crits (still better to remove the extra die for LWF, and not spend tokens)
    if (attack_setup.accuracy_corrector)
    {
        int hits = attack_results[DieResult.Hit];
        int crits = attack_results[DieResult.Crit];
        if (((hits + crits) <  2) ||
            (hits == 2 && crits == 0) ||
            ((hits + crits) == 2 && attack_setup.one_damage_on_hit))
        {
            // TODO: This is actually a bit too optimistic/simplistic...
            // In some cases it's fair to just conclude that we could have foreseen how many hits we
            // could get via modification and thus decided to use AC *instead*, but in cases of
            // stuff like spending target locks for rerolls, it's impossible to perfectly predict.
            // Thus we should really have actual logic that decides the best thing to do
            // probabilistically, and in some cases "wastes" tokens due to bad rerolls.
            attack_setup = initial_attack_setup;    // Undo any token spending

            foreach (ref r; attack_results) r = 0;  // Cancel all results
            attack_results[DieResult.Hit] = 2;      // Add two hits to the result
            // No more modifaction

            // TODO: We probably need to actually change the dice themselves eventually
            // to properly handle things like lightweight frame.
        }
    }

    return attack_results;
}





void attacker_modify_defense_dice(ref const(AttackSetup) attack_setup,
                                  ref const(DefenseSetup) defense_setup,
                                  int[DieResult.Num] attack_results,
                                  ref DiceState defense_dice,
                                  ref TokenState defense_tokens)
{
    // Find one evade and turn it to a focus
    if (attack_setup.juke)
        defense_dice.change_dice(DieResult.Evade, DieResult.Focus, 1);
}

void defender_modify_defense_dice(ref const(AttackSetup) attack_setup,
                                  ref const(DefenseSetup) defense_setup,
                                  int[DieResult.Num] attack_results,
                                  ref DiceState defense_dice,
                                  ref TokenState defense_tokens)
{
    // Find one blank and turn it to an evade
    if (defense_setup.autothrusters)
        defense_dice.change_dice(DieResult.Blank, DieResult.Evade, 1);

    // If we have any focus results and no focus token, reroll our focuses
    if (defense_tokens.focus == 0 && defense_setup.wired)
    {
        defense_dice.reroll_defense_dice(DieResult.Focus);
    }

    // Spend regular focus or evade tokens?
    if (defense_tokens.focus > 0 || defense_tokens.evade > 0)
    {
        int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit] - defense_dice.count(DieResult.Evade);

        bool can_spend_focus = defense_tokens.focus > 0 && defense_dice.count(DieResult.Focus) > 0;

        if (uncanceled_hits > 0 && (can_spend_focus || defense_tokens.evade > 0))
        {
            // For now simple logic:
            // Cancel all hits with just a focus? Do it.
            // Cancel all hits with just evade tokens? Do that.
            // If attacker has juke, flip this order - it's usually better to hang on to focus tokens vs. juke
            //   NOTE: Optimal strategy here depends on quite a lot of factors, but this is good enough in most cases
            //   One improvement to the logic would be to only invoke this behavior if # remaining attacks > # focus tokens
            // Otherwise both.

            // TODO: Probably makes sense to always prefer spending fewer tokens. i.e. if we can spend one focus vs. two evades
            // even in the presence of Juke, etc. Certainly should make sense for smallish dice counts. TEST.
            // Obviously optimal would consider all the effects and how many attacks and what tokens each person has, but 
            // we should be able to get close enough for our purposes.

            bool can_cancel_all_with_focus = can_spend_focus && (defense_dice.count(DieResult.Focus) >= uncanceled_hits);
            bool can_cancel_all_with_evade = defense_tokens.evade >= uncanceled_hits;

            bool spent_focus = false;
            int spent_evade_tokens = 0;

            // Do we need to spend both to cancel all hits?
            if (!can_cancel_all_with_focus && !can_cancel_all_with_evade)
            {
                int uncancelled_hits_after_focus = uncanceled_hits;
                if (can_spend_focus)
                {
                    spent_focus = can_spend_focus;
                    uncancelled_hits_after_focus = max(0, uncanceled_hits - defense_dice.count(DieResult.Focus));
                }
                spent_evade_tokens = min(defense_tokens.evade, uncancelled_hits_after_focus);
            }
            else if (!attack_setup.juke)        // No juke - hold onto evade primarily
            {
                if (can_cancel_all_with_focus)
                    spent_focus = true;
                else
                    spent_evade_tokens = uncanceled_hits;
            }
            else                                // Juke - hold on to focus primarily
            {
                if (can_cancel_all_with_evade)
                    spent_evade_tokens = uncanceled_hits;
                else
                    spent_focus = true;
            }

            if (spent_focus)
            {
                uncanceled_hits -= defense_dice.count(DieResult.Focus);
                defense_dice.change_dice(DieResult.Focus, DieResult.Evade);
                --defense_tokens.focus;
            }

            // Evade tokens add defense dice to the pool
            uncanceled_hits -= spent_evade_tokens;
            defense_dice.results[DieResult.Evade] += spent_evade_tokens;
            defense_tokens.evade -= spent_evade_tokens;            
        }

        // Sanity
        assert(defense_tokens.evade >= 0);
        assert(defense_tokens.focus >= 0);
        assert(uncanceled_hits <= 0 || defense_tokens.evade == 0);
    }
}

int[DieResult.Num] roll_and_modify_defense_dice(ref AttackSetup attack_setup,
                                                ref const(DefenseSetup) defense_setup,
                                                ref TokenState defense_tokens,
                                                int[DieResult.Num] attack_results)
{
    // Roll Defense Dice
    DiceState defense_dice;
    foreach (i; 0 .. defense_setup.dice)
        defense_dice.add_random_defense_die();

    // Modify Defense Dice
    attacker_modify_defense_dice(attack_setup, defense_setup, attack_results, defense_dice, defense_tokens);
    defender_modify_defense_dice(attack_setup, defense_setup, attack_results, defense_dice, defense_tokens);

    // Done modifying defense dice - compute final defense results
    return defense_dice.count_all();
}




// Modifies input setups to adjust for token spending
// Also returned as part of simulation result, but convenient to modify in place for multiple attacks
private int[DieResult.Num] simulate_single_attack(ref AttackSetup attack_setup,
                                                  ref const(DefenseSetup) defense_setup,
                                                  ref TokenState defense_tokens,
                                                  bool trigger_after_attack = true)
{
    auto attack_results  = roll_and_modify_attack_dice(attack_setup, defense_setup);
    auto defense_results = roll_and_modify_defense_dice(attack_setup, defense_setup, defense_tokens, attack_results);

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
    if (attack_setup.one_damage_on_hit && attack_hit)
    {
        attack_results[DieResult.Hit] = 1;
        attack_results[DieResult.Crit] = 0;
    }
    
    // Trigger any "after attacking" abilities if request
    if (trigger_after_attack)
    {
        // Update any abilities that trigger "after attacking" or "after defending"
        if (attack_setup.fire_control_system)
        {
            // TODO: Handle multi-target-lock stuff... really only an issue with Redline and so on
            attack_setup.target_lock_count = max(attack_setup.target_lock_count, 1);
        }
    }

    return attack_results;
}


SimulationResult simulate_attack(AttackSetup attack_setup, const(DefenseSetup) defense_setup)
{
    // TODO: Sanity checks on inputs?

    auto initial_attack_setup  = attack_setup;

    TokenState defense_tokens;
    defense_tokens.focus  = defense_setup.initial_focus_token_count;
    defense_tokens.evade  = defense_setup.initial_evade_token_count;
    defense_tokens.stress = defense_setup.initial_stress_token_count;

    // Simulate first attack
    // TODO: We'll eventually need to pass some hints into this about the fact that there is a second attack
    // as it does change the optimal token spend strategies and so on somewhat.
    // Also upgrades matter here (FCS, etc).
    // NOTE: Attack/defense setup passed by reference as tokens are modified in place

    int[DieResult.Num] attack_results;
    bool first_attack_hit = (attack_results[DieResult.Hit] != 0 || attack_results[DieResult.Crit] != 0);
    
    if (attack_setup.type == MultiAttackType.Single)
    {
        attack_results = simulate_single_attack(attack_setup, defense_setup, defense_tokens, true);
    }
    else if (attack_setup.type == MultiAttackType.SecondaryPerformTwice)
    {
        // We DO NOT trigger "after attack" type abilities between two "secondary perfom twice" attacks
        attack_results    = simulate_single_attack(attack_setup, defense_setup, defense_tokens, false);
        attack_results[] += simulate_single_attack(attack_setup, defense_setup, defense_tokens, true)[];
    }    
    else if (attack_setup.type == MultiAttackType.AfterAttack)
    {
        // After attack abilities trigger after both of these
        attack_results    = simulate_single_attack(attack_setup, defense_setup, defense_tokens, true);
        attack_results[] += simulate_single_attack(attack_setup, defense_setup, defense_tokens, true)[];
    }
    else if (attack_setup.type == MultiAttackType.AfterAttackDoesNotHit && !first_attack_hit)
    {
        // After attack abilities trigger after both of these
        attack_results    = simulate_single_attack(attack_setup, defense_setup, defense_tokens, true);
        // Only do second attack if the first one missed
        if (attack_results[DieResult.Hit] == 0 && attack_results[DieResult.Crit] == 0)
            attack_results[] += simulate_single_attack(attack_setup, defense_setup, defense_tokens, true)[];
    }
    else
    {
        assert(false);  // Unknown attack type
    }

    // Sanity checks on token spending
    assert(attack_setup.target_lock_count >= 0);        // Possible to gain target locks due to FCS
    assert(attack_setup.focus_token_count >= 0 && attack_setup.focus_token_count <= initial_attack_setup.focus_token_count);
    assert(attack_setup.stress_token_count >= 0);
    assert(defense_tokens.evade >= 0);
    assert(defense_tokens.focus >= 0);
    assert(defense_tokens.stress >= 0);

    // Compute final results of this simulation step
    SimulationResult result;
    result.trial_count = 1;

    result.hits  = attack_results[DieResult.Hit];
    result.crits = attack_results[DieResult.Crit];

    result.attack_delta_focus_tokens  = attack_setup.focus_token_count  - initial_attack_setup.focus_token_count ; 
    result.attack_delta_target_locks  = attack_setup.target_lock_count  - initial_attack_setup.target_lock_count ; 
    result.attack_delta_stress        = attack_setup.stress_token_count - initial_attack_setup.stress_token_count;
    result.defense_delta_focus_tokens = defense_tokens.focus     - defense_setup.initial_focus_token_count ;
    result.defense_delta_evade_tokens = defense_tokens.evade     - defense_setup.initial_evade_token_count ;
    result.defense_delta_stress       = defense_tokens.stress    - defense_setup.initial_stress_token_count; 

    return result;
}
