// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.13;

interface IHatsElectionsEligibility {
    event ElectionOpened(uint128 nextTermEnd);
    event ElectionCompleted(uint128 termEnd, address[] winners);
    event NewTermStarted(uint128 termEnd);
    event Recalled(uint128 termEnd, address[] accounts);

    /// @notice Returns the first second after the current term ends.
    /// @dev Also serves as the id for the current term.
    function currentTermEnd() external view returns (uint128);

    /// @notice Returns the first second after the next term ends.
    /// @dev Also serves as the id for the next term.
    function nextTermEnd() external view returns (uint128);

    /// @notice Returns the election status (open or closed) for a given term end.
    /// @param termEnd The term end timestamp to query.
    function electionStatus(
        uint128 termEnd
    ) external view returns (bool isElectionOpen);

    /// @notice Returns whether a candidate was elected in a given term.
    /// @param termEnd The term end timestamp to query.
    /// @param candidate The address of the candidate.
    function electionResults(
        uint128 termEnd,
        address candidate
    ) external view returns (bool elected);

    /// @notice Returns the BALLOT_BOX_HAT constant.
    function BALLOT_BOX_HAT() external pure returns (uint256);

    /// @notice Returns the ADMIN_HAT constant.
    function ADMIN_HAT() external pure returns (uint256);

    /**
     * @notice Submit the results of an election for a specified term.
     * @dev Only callable by the wearer(s) of the BALLOT_BOX_HAT.
     * @param _termEnd The id of the term for which the election results are being submitted.
     * @param _winners The addresses of the winners of the election.
     */
    function elect(uint128 _termEnd, address[] calldata _winners) external;

    /**
     * @notice Submit the results of a recall election for a specified term.
     * @dev Only callable by the wearer(s) of the BALLOT_BOX_HAT.
     * @param _termEnd The id of the term for which the recall results are being submitted.
     * @param _recallees The addresses to be recalled.
     */
    function recall(uint128 _termEnd, address[] calldata _recallees) external;

    /**
     * @notice Set the next term and open the election for it.
     * @dev Only callable by the wearer(s) of the ADMIN_HAT.
     * @param _newTermEnd The id of the term that will be opened.
     */
    function setNextTerm(uint128 _newTermEnd) external;

    /**
     * @notice Start the next term, updating the current term.
     * @dev Can be called by anyone, but will revert if conditions are not met.
     */
    function startNextTerm() external;

    /**
     * @notice Determine the eligibility and standing of a wearer for a hat.
     * @param _wearer The address of the hat wearer.
     * @param _hatId The ID of the hat.
     * @return eligible True if the wearer is eligible for the hat.
     * @return standing True if the wearer is in good standing.
     */
    function getWearerStatus(
        address _wearer,
        uint256 _hatId
    ) external view returns (bool eligible, bool standing);
}
