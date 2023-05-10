// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DeepFakeDetector {
    using SafeERC20 for IERC20;
    IERC20 public immutable defaultCurrency;

    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 3600;
    bytes32 public immutable defaultIdentifier;

    struct ImageAssertion {
        bytes32 imageId; // image ID -> the hash of the image
        string imageUrl; // the IPFS link where the image is stored
        address asserter; // the address that made the assertion
        bool resolved; // whether the assertion has been resolved
    }

    mapping(bytes32 => ImageAssertion) imageAssertions; // mapping from IDs to Image Assertions

    event ImageAsserted(
        bytes32 indexed imageId,
        string imageUrl,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    event ImageAssertionResolved(
        bytes32 indexed imageId,
        string imageUrl,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    constructor() {
        defaultCurrency = IERC20(0x07865c6E87B9F70255377e024ace6630C1Eaa37F); // USDC on Goerli
        oo = OptimisticOracleV3Interface(
            0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB
        ); // OOV3 on Goerli
        defaultIdentifier = oo.defaultIdentifier();
    }

    // For a given assertionId, returns a boolean indicating whether the image is accessible and the image itself.
    function getImage(
        bytes32 assertionId
    ) public view returns (bool, string memory) {
        if (!imageAssertions[assertionId].resolved) return (false, "");
        return (true, imageAssertions[assertionId].imageUrl);
    }

    function assertDataFor(
        bytes32 imageId,
        string calldata imageUrl,
        address asserter
    ) public returns (bytes32 assertionId) {
        asserter = asserter == address(0) ? msg.sender : asserter;
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Image asserted at url: ",
                imageUrl,
                " for imageID: 0x",
                ClaimData.toUtf8Bytes(imageId),
                " and asserter: 0x",
                ClaimData.toUtf8BytesAddress(asserter),
                ClaimData.toUtf8BytesAddress(asserter),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is not a deepfake."
            ),
            asserter,
            address(this),
            address(0),
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0)
        );

        imageAssertions[assertionId] = ImageAssertion(
            imageId,
            imageUrl,
            asserter,
            false
        );

        emit ImageAsserted(imageId, imageUrl, asserter, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            imageAssertions[assertionId].resolved = true;
            ImageAssertion memory imageAssertion = imageAssertions[assertionId];
            emit ImageAssertionResolved(
                imageAssertion.imageId,
                imageAssertion.imageUrl,
                imageAssertion.asserter,
                assertionId
            );
        } else delete imageAssertions[assertionId];
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public {}
}
