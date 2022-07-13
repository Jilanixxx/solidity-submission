// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract CrowdFund is IERC721Receiver {
    event Launch(
        uint256 id,
        address indexed creator,
        uint256 goal,
        uint32 startAt,
        uint32 endAt
    );
    event End();
    event Pledge(
        uint256 indexed tokenId,
        address indexed caller,
        address indexed contractAddress
    );
    event Unpledge(
        uint256 indexed tokenId,
        address indexed caller,
        address indexed contractAddress
    );
    event Claim(uint256 id);
    event Refund(
        uint256 indexed tokenId,
        address indexed contractAddress,
        address indexed caller
    );

    address public creator;
    uint256 public goal;
    uint256 public pledged = 0;
    uint256 endAt;
    bool claimed;
    bool started;
    bool public ended;
    bool public success;

    struct Nft {
        address donator;
        address contractAddress;
        uint256 tokenId;
        bool pledged;
    }
    mapping(uint256 => Nft) public nftsPledged;

    mapping(uint256 => bool) public nftsClaimed;

    modifier onlyCreator() {
        require(creator == msg.sender, "not creator");
        _;
    }

    modifier onlyDonator(uint256 _id) {
        Nft memory nft = nftsPledged[_id];
        require(nft.donator == msg.sender, "not donator");
        require(nft.pledged, "not pledged");
        _;
    }

    modifier onlyNotClaimed(uint256 _id) {
        require(!nftsClaimed[_id], "nft claimed");
        _;
    }

    constructor(uint256 _goal, uint256 _endAt) {
        creator = msg.sender;
        goal = _goal;
        endAt = block.timestamp + _endAt;
        started = true;
    }

    // Pledge NFT to crowdfund
    function pledge(uint256 tokenId, address _contractAddress) external {
        require(_contractAddress != address(0), "not valid contract");
        require(!ended, "ended");
        require(block.timestamp < endAt, "over");

        IERC721(_contractAddress).transferFrom(
            msg.sender,
            address(this),
            tokenId
        );
        nftsPledged[pledged] = Nft(msg.sender, _contractAddress, tokenId, true);
        pledged++;
        emit Pledge(tokenId, msg.sender, _contractAddress);
    }

    // Unpledge NFT from crowdfund
    function unpledge(uint256 _id) external onlyDonator(_id) {
        Nft storage nft = nftsPledged[_id];
        require(!ended, "ended");
        IERC721(nft.contractAddress).transferFrom(
            address(this),
            msg.sender,
            nft.tokenId
        );
        // sets pledged back to false
        nft.pledged = false;
        // as NFT is unpledged, claimed is set to true
        nftsClaimed[_id] = true;
        pledged--;
        emit Unpledge(nft.tokenId, msg.sender, nft.contractAddress);
    }

    function end() external onlyCreator {
        require(block.timestamp > endAt, "not over");
        require(!ended, "ended");
        claimed = true;
        ended = true;
        endAt = 0;
        started = false;
        // success is true only if goal is reached or exceeded
        if (pledged >= goal) {
            success = true;
        } else {
            success = false;
        }
        emit End();
    }

    // withdraw NFT if crowdfund is not a success
    function withdrawNft(uint256 _id)
        external
        onlyDonator(_id)
        onlyNotClaimed(_id)
    {
        require(!success, "is successful");
        require(ended, "not ended");
        IERC721(nftsPledged[_id].contractAddress).transferFrom(
            address(this),
            msg.sender,
            nftsPledged[_id].tokenId
        );
        uint256 tokenId = nftsPledged[_id].tokenId;
        address contractAddress = nftsPledged[_id].contractAddress;
        delete nftsPledged[_id];
        nftsClaimed[_id] = true;
        emit Refund(tokenId, contractAddress, msg.sender);
    }

    // Creator can claim pledged NFTs
    function claimNft(uint256 _id) external onlyCreator onlyNotClaimed(_id) {
        require(success, "was not successful");
        require(ended, "not ended");
        IERC721(nftsPledged[_id].contractAddress).transferFrom(
            address(this),
            creator,
            nftsPledged[_id].tokenId
        );
        delete nftsPledged[_id];
        nftsClaimed[_id] = true;
        emit Claim(_id);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return bytes4(this.onERC721Received.selector);
    }
}
