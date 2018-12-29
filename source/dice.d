import math;

import std.math;
import std.algorithm;

// We need a value that is large enough to mean "all of the dice", but no so large as to overflow
// easily when we add multiple such values together (ex. int.max). This is that value.
// The specifics of this value should never be relied upon, and indeed it should be completely fine
// to mix different values technically - the main purpose in this definition is just for clarity
// of intention in the code.
public immutable int k_all_dice_count = 1000;

public enum DieResult : int
{
    Blank = 0,
    Focus = 1,
    Hit = 2,
    // Minor optimization... hit/crit are mutually exclusive with evade, so reuse the index
    Evade = 2,
    Crit = 3,
    Num
};

public struct DiceState
{
    // Count number of dice for each result
    // Count rerolled dice separately (can only reroll each die once)
    // "Final" results cannot be modified, only cancelled
    ubyte[DieResult.Num] results;
    ubyte[DieResult.Num] rerolled_results;
    ubyte[DieResult.Num] final_results;

    // Cancel all dice/reinitialize
    void cancel_all()
    {
        results[] = 0;
        rerolled_results[] = 0;
        final_results[] = 0;
    }

    // Cancel all non-final dice
    void cancel_mutable()
    {
        results[] = 0;
        rerolled_results[] = 0;
    }

    // "Finalize" dice state "final_results"
    // Also removes all focus and blank results to reduce unnecessary state divergence
    void finalize()
    {
        final_results[] += results[] + rerolled_results[];
        final_results[DieResult.Blank] = 0;
        final_results[DieResult.Focus] = 0;

        results[] = 0;
        rerolled_results[] = 0;
    }

    // Utilities
    pure int count(DieResult type) const
    {
        return results[type] + rerolled_results[type] + final_results[type];
    }
    // As above, but excludes "final", immutable dice
    pure int count_mutable(DieResult type) const
    {
        return results[type] + rerolled_results[type];
    }
    // Check if all dice are blank
    pure bool are_all_blank()
    {
        return count(DieResult.Hit) == 0 && count(DieResult.Crit) == 0 && count(DieResult.Focus) == 0;
    }

    // Removes dice that we are able to reroll from results and returns the
    // number that were removed. Caller should add rerolled_results based on this.
    int remove_dice_for_reroll(DieResult from, int max_count = int.max)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);

        int rerolled_count = min(results[from], max_count);
        results[from] -= rerolled_count;

        return rerolled_count;
    }

    // Prefers rerolling blanks, secondarily focus results
    int remove_dice_for_reroll_blank_focus(int max_count = int.max)
    {
        int rerolled_results = remove_dice_for_reroll(DieResult.Blank, max_count);
        if (rerolled_results >= max_count) return rerolled_results;

        rerolled_results += remove_dice_for_reroll(DieResult.Focus,  max_count - rerolled_results);
        return rerolled_results;
    }

    // Prefers changing rerolled dice first where limited as they are more constrained
    // NOTE: Cannot change final results by definition
    int change_dice(DieResult from, DieResult to, int max_count = int.max)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);

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

    // As above, but the changed dice are finalized and cannot be further modified at all
    // Generally this is used when modifying your own dice with ex. Palpatine, so will
    // prefer to change rerolled dice first (although this currently never comes up with
    // effects present in the game).
    int change_dice_final(DieResult from, DieResult to, int max_count)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);

        // Change rerolled dice first
        int changed_count = 0;

        int delta = min(rerolled_results[from], max_count - changed_count);
        if (delta > 0)
        {
            rerolled_results[from] -= delta;
            final_results[to]      += delta;
            changed_count          += delta;
        }
        // Then regular ones
        delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from]       -= delta;
            final_results[to]   += delta;
            changed_count       += delta;
        }

        return changed_count;
    }

    // Like above, but the changed dice cannot be rerolled
    // Because this is generally used when modifying *opponents* dice, we prefer
    // to change non-rerolled dice first to add additional constraints.
    // Ex. M9G8 forced reroll and sensor jammer can cause two separate dice
    // to be unable to be rerolled by the attacker.
    int change_dice_no_reroll(DieResult from, DieResult to, int max_count)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);

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

    // Prefers changing blanks, secondarily focus results
    int change_blank_focus(DieResult to, int max_count = int.max)
    {
        int changed_results = change_dice(DieResult.Blank, to, max_count);
        if (changed_results >= max_count) return changed_results;

        changed_results += change_dice(DieResult.Focus, to, max_count - changed_results);
        return changed_results;
    }
}


// delegate params are (blank, focus, hit, crit, probability)
public void roll_attack_dice(int dice_count, void delegate(int, int, int, int, double) dg)
{
    // TODO: Maybe optimize/specialize this more for small numbers of dice.
    // Rerolling 1 die is likely to be more common than large counts.
    for (int crit = 0; crit <= dice_count; ++crit)
    {
        for (int hit = 0; hit <= (dice_count - crit); ++hit)
        {
            for (int focus = 0; focus <= (dice_count - crit - hit); ++focus)
            {
                int blank = dice_count - crit - hit - focus;
                assert(blank >= 0);

                double roll_probability = compute_attack_roll_probability(blank, focus, hit, crit);
                dg(blank, focus, hit, crit, roll_probability);
            }
        }
    }
}

// delegate params are (blank, focus, evade, probability)
public void roll_defense_dice(int dice_count, void delegate(int, int, int, double) dg)
{
    // TODO: Maybe optimize/specialize this more for small numbers of dice.
    // Rerolling 1 die is likely to be more common than large counts.
    for (int evade = 0; evade <= dice_count; ++evade)
    {
        for (int focus = 0; focus <= (dice_count - evade); ++focus)
        {
            int blank = dice_count - focus - evade;
            assert(blank >= 0);

            double roll_probability = compute_defense_roll_probability(blank, focus, evade);
            dg(blank, focus, evade, roll_probability);
        }
    }
}