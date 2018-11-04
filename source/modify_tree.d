import simulation_state2;

public struct ModifyTreeNode
{
    // States before and after calling the modify function
    // NOTE: These states will often match other than dice being removed for reroll.
    SimulationState before;
    SimulationState after;
    int reroll_count = 0;

    // From this point forward (computed via backtracking)
    double child_probability = 1.0;         // Normalized across all siblings; reroll probability
    double expected_damage = 0.0;

    // Children are contiguous in the array
    int depth = 0;              // How many parents before we reach the root
    size_t child_count = 0;
    size_t first_child_index = 0;
};
