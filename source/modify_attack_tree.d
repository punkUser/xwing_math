import simulation_state2;
import simulation_setup2;
import modify_attack_dice : modify_attack_dice;
import modify_tree;
import dice;

private void modify_attack_tree(const(SimulationSetup2) setup,
                                ref ModifyTreeNode[] nodes,
                                int current_node)
{
    nodes[current_node].after = nodes[current_node].before;
    nodes[current_node].reroll_count = modify_attack_dice(setup, nodes[current_node].after);
    if (nodes[current_node].reroll_count == 0)
    {
        // Base case; done modifying dice
        nodes[current_node].expected_damage =
            nodes[current_node].after.attack_dice.count(DieResult.Hit) +
            nodes[current_node].after.attack_dice.count(DieResult.Crit);
        return;
    }

    // Make all the reroll nodes and append them contiguously to the list
    int first_child_index = cast(int)nodes.length;

    roll_attack_dice(nodes[current_node].reroll_count, (int blank, int focus, int hit, int crit, double probability) {
        ModifyTreeNode new_node;

        new_node.child_probability = probability;
        new_node.depth = nodes[current_node].depth + 1;

        new_node.before = nodes[current_node].after;
        new_node.before.attack_dice.rerolled_results[DieResult.Crit]  += crit;
        new_node.before.attack_dice.rerolled_results[DieResult.Hit]   += hit;
        new_node.before.attack_dice.rerolled_results[DieResult.Focus] += focus;
        new_node.before.attack_dice.rerolled_results[DieResult.Blank] += blank;
        new_node.before.probability *= probability;

        nodes ~= new_node;
    });
    int last_child_index = cast(int)nodes.length;     // Exclusive

    nodes[current_node].first_child_index = first_child_index;
    nodes[current_node].child_count = last_child_index - first_child_index;

    double expected_damage = 0.0;
    foreach (child_node; first_child_index .. last_child_index)
    {
        modify_attack_tree(setup, nodes, child_node);
        expected_damage += nodes[child_node].child_probability * nodes[child_node].expected_damage;
    }
    nodes[current_node].expected_damage = expected_damage;
}



public ModifyTreeNode[] compute_modify_attack_tree(const(SimulationSetup2) setup,
                                                   TokenState2 attack_tokens,
                                                   DiceState attack_dice)
{
    auto nodes = new ModifyTreeNode[1];
    nodes[0].before.attack_tokens = attack_tokens;
    nodes[0].before.attack_dice   = attack_dice;
    nodes[0].before.probability   = 1.0;
    modify_attack_tree(setup, nodes, 0);
    return nodes;
}
