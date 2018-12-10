import simulation_state2;
import simulation_setup2;
import modify_defense_dice : modify_defense_dice_root, compute_uncanceled_damage;
import modify_tree;
import dice;

// Returns expected damage
private void modify_defense_tree(const(SimulationSetup) setup,
                                 ref ModifyTreeNode[] nodes,
                                 int current_node)
{
    nodes[current_node].after = nodes[current_node].before;

    StateFork fork = modify_defense_dice_root(setup, nodes[current_node].after);
    if (!fork.required())
    {
        // NOTE: Currently using defense dice neutralize approximation as it gives the best insight into the
        // decision making.
        double expected_damage = compute_uncanceled_damage(setup, nodes[current_node].after);

        // Base case; done modifying dice
        nodes[current_node].reroll_count = 0;       // TODO: Probably switch to a fork in struct
        nodes[current_node].expected_damage = expected_damage;
        return;
    }

    // Make all the reroll nodes and append them contiguously to the list
    int first_child_index = cast(int)nodes.length;

    // TODO: Handle other cases
    assert(fork.type == StateForkType.Reroll);

    nodes[current_node].reroll_count = fork.roll_count;
    roll_defense_dice!true(nodes[current_node].after, nodes[current_node].reroll_count, (SimulationState next_state, double probability) {
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
        modify_defense_tree(setup, nodes, child_node);
        expected_damage += nodes[child_node].child_probability * nodes[child_node].expected_damage;
    }
    nodes[current_node].expected_damage = expected_damage;
}



public ModifyTreeNode[] compute_modify_defense_tree(const(SimulationSetup) setup,
                                                    DiceState attack_dice,
                                                    TokenState defense_tokens,
                                                    DiceState defense_dice)
{
    auto nodes = new ModifyTreeNode[1];
    
    // NOTE: These need to be "finalized" before defense mods
    attack_dice.finalize();
    nodes[0].before.attack_dice    = attack_dice;

    nodes[0].before.defense_tokens = defense_tokens;
    nodes[0].before.defense_dice   = defense_dice;
    nodes[0].before.probability    = 1.0;
    modify_defense_tree(setup, nodes, 0);
    return nodes;
}
