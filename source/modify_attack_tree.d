import simulation_state2;
import simulation_setup2;
import modify_attack_dice : modify_attack_dice;
import modify_tree;
import dice;

private void modify_attack_tree(const(SimulationSetup) setup,
                                ref ModifyTreeNode[] nodes,
                                int current_node)
{
    nodes[current_node].after = nodes[current_node].before;

    StateFork fork = modify_attack_dice(setup, nodes[current_node].after);
    if (!fork.required())
    {
        // Base case; done modifying dice
        nodes[current_node].reroll_count = 0;               // TODO: Probably switch to a fork in struct
        nodes[current_node].expected_damage =
            nodes[current_node].after.attack_dice.count(DieResult.Hit) +
            nodes[current_node].after.attack_dice.count(DieResult.Crit);
        return;
    }

    // Make all the child nodes and append them contiguously to the list
    int first_child_index = cast(int)nodes.length;

    nodes[current_node].reroll_count = fork.roll_count;     // TODO: Probably switch to a fork in struct
    fork_attack_state(nodes[current_node].after, fork, (SimulationState next_state, double probability) {
        ModifyTreeNode new_node;
        new_node.child_probability = probability;
        new_node.depth = nodes[current_node].depth + 1;
        new_node.before = next_state;
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



public ModifyTreeNode[] compute_modify_attack_tree(const(SimulationSetup) setup,
                                                   TokenState attack_tokens,
                                                   DiceState attack_dice)
{
    auto nodes = new ModifyTreeNode[1];
    nodes[0].before.attack_tokens = attack_tokens;
    nodes[0].before.attack_dice   = attack_dice;
    nodes[0].before.probability   = 1.0;
    modify_attack_tree(setup, nodes, 0);
    return nodes;
}
