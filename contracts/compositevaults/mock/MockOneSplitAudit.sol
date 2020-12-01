import "../../interfaces/OneSplitAudit.sol";

contract MockOneSplitAudit is OneSplitAudit {
    function swap(
        address fromToken,
        address destToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata distribution,
        uint256 flags
    )
    external
    override
    payable
    returns (uint256 returnAmount) {
        return 0;
    }

    function getExpectedReturn(
        address fromToken,
        address destToken,
        uint256 amount,
        uint256 parts,
        uint256 flags // See constants in IOneSplit.sol
    )
    external
    override
    view
    returns (
        uint256 returnAmount,
        uint256[] memory distribution
    ) {
        returnAmount = amount;
    }
}