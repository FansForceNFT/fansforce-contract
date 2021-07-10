// SPDX-License-Identifier: GPL-3

pragma solidity ^0.8.0;

import "./NFTShareTemp.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

contract FansForceNFT is Initializable, ContextUpgradeable, AccessControlEnumerableUpgradeable,
ERC721EnumerableUpgradeable, ERC721BurnableUpgradeable, ERC721PausableUpgradeable, ERC721URIStorageUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    using SafeMathUpgradeable for uint256;
    using StringsUpgradeable for string;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    //  nft share info
    struct ShareInfo {
        address erc20;
        uint256 ownerRate;
        string tokenName;
        string tokenSymbol;
        uint256 tokenSupply;
        uint8 tokenDecimal;
    }

    // nft share info
    struct NFTInfo {
        address ownerAddress;
        address creatorAddress;
        string nftName;
        string nftSymbol;
        string nftLink;
        string nftMetaData;
        bool pending;
        bool sharing;
        ShareInfo shareInfo;
    }

    // erc20 contract template
    address private _shareErc20Temp;
    // nft token id counter
    CountersUpgradeable.Counter private _tokenIdTracker;
    // nft info
    mapping(uint256 => NFTInfo) public _nftInfos;

    string private _baseTokenURI;

    event FansNFTCreated(address indexed sender, address indexed ownerAddress, address indexed creatorAddress, uint256 tokenId);
    event FansNFTSharing(address indexed sender, uint256 tokenId, address erc20);

    function initialize(string memory name, string memory symbol) public virtual initializer {
        __FansNFT_init(name, symbol);
    }

    /**
    * user create nft
    * ownerAddress: the nft owner address
    * creatorAddress: the nft creatorAddress
    * nftName: the nft name
    * nftSymbol: the nft symbol
    * nftLink: the nft link
    * nftMetaData: nft meta data,input by user
    */
    function create(
        address ownerAddress,
        address creatorAddress,
        string memory nftName,
        string memory nftSymbol,
        string memory nftLink,
        string memory nftMetaData) external virtual {

        uint256 tokenId = _tokenIdTracker.current();
        _nftInfos[tokenId].ownerAddress = ownerAddress;
        _nftInfos[tokenId].creatorAddress = creatorAddress;
        _nftInfos[tokenId].nftName = nftName;
        _nftInfos[tokenId].nftSymbol = nftSymbol;
        _nftInfos[tokenId].nftLink = nftLink;
        _nftInfos[tokenId].nftMetaData = nftMetaData;
        _nftInfos[tokenId].pending = true;

        // create nft to owner address
        _mint(ownerAddress, tokenId);

        ERC721URIStorageUpgradeable._setTokenURI(tokenId, nftLink);
        _tokenIdTracker.increment();

        emit FansNFTCreated(msg.sender, ownerAddress, creatorAddress, tokenId);

    }

    /**
    * share nft,it's will share nft to erc20 token, issue tokenSupply*ownerRate/100 to owner,
    * and remain to creator
    * tokenId: the nft token id
    * tokenName: erc20 token name
    * tokenSymbol: erc20 token symbol
    * tokenSupply: erc20 token supply
    * tokenDecimal： erc20 token decimal
    * ownerRate: the proportion of erc20 token held by owner
    */
    function share(
        uint256 tokenId,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 tokenSupply,
        uint8 tokenDecimal,
        uint256 ownerRate) external virtual {

        uint256 ownerBalance = (tokenSupply * ownerRate) / 100;
        require(ownerBalance <= tokenSupply, "share:params error");
        require(tokenDecimal < 19, "tokenDecimal gather than 18");

        address owner = ERC721Upgradeable.ownerOf(tokenId);
        address creator = _nftInfos[tokenId].creatorAddress;
        require(owner == _msgSender() || creator == _msgSender(), "share:only owner or creator can share ");
        require(!_nftInfos[tokenId].sharing, "share:tokenId already sharing");

        // nft share to erc20
        address _erc20 = ClonesUpgradeable.clone(_shareErc20Temp);
        NFTShareTemp(_erc20).initialize(tokenName, tokenSymbol, tokenDecimal, address(this), tokenId);

        _nftInfos[tokenId].sharing = true;
        _nftInfos[tokenId].shareInfo.erc20 = _erc20;
        _nftInfos[tokenId].shareInfo.ownerRate = ownerRate;
        _nftInfos[tokenId].shareInfo.tokenDecimal = tokenDecimal;
        _nftInfos[tokenId].shareInfo.tokenName = tokenName;
        _nftInfos[tokenId].shareInfo.tokenSupply = tokenSupply;
        _nftInfos[tokenId].shareInfo.tokenSymbol = tokenSymbol;

        // mint erc20 token to owner
        NFTShareTemp(_erc20).mint(owner, ownerBalance);
        // mint erc20 token to creator
        NFTShareTemp(_erc20).mint(creator, tokenSupply - ownerBalance);

        emit FansNFTSharing(_msgSender(), tokenId, _erc20);

    }

    function setNFTShareTemp(address shareErc20Temp) public virtual {
        require(shareErc20Temp != address(0), "shareErc20Temp invalid");
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "setShareErc20Temp: must have ADMIN role to change this");
        _shareErc20Temp = shareErc20Temp;
    }

    function getNFTShareTemp() public view virtual returns (address){
        return _shareErc20Temp;
    }

    function getNFTInfo(uint256 tokenId) public view virtual returns (NFTInfo memory){
        return _nftInfos[tokenId];
    }

    function isNFTShared(uint256 tokenId) public view virtual returns (bool){
        return _nftInfos[tokenId].sharing;
    }

    function setBaseTokenURI(string memory baseTokenURI) public virtual {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "setBaseTokenURI: must have ADMIN role to change this");
        _baseTokenURI = baseTokenURI;
    }

    /**
    * Pauses all token transfers.
    *
    * See {ERC721Pausable} and {Pausable-_pause}.
    *
    * Requirements:
    *
    * - the caller must have the `PAUSER_ROLE`.
    */
    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "pause: must have pauser role to pause");
        _pause();
    }

    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "unpause: must have pauser role to unpause");
        _unpause();
    }

    /**
    *  See {IERC721Metadata-tokenURI}.
    */
    function tokenURI(uint256 tokenId) public view virtual override(ERC721URIStorageUpgradeable, ERC721Upgradeable) returns (string memory) {
        return ERC721URIStorageUpgradeable.tokenURI(tokenId);
    }

    function getSharingAddress(uint256 tokenId) public view virtual returns (address){
        return _nftInfos[tokenId].shareInfo.erc20;
    }

    /**
    * See {IERC165-supportsInterface}.
    */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerableUpgradeable, ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function __FansNFT_init(string memory name, string memory symbol) internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __ERC721Enumerable_init_unchained();
        __ERC721Burnable_init_unchained();
        __Pausable_init_unchained();
        __ERC721Pausable_init_unchained();
        __ERC721Other_init_unchained();
    }

    function __ERC721Other_init_unchained() internal initializer {
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _baseTokenURI = "";
    }

    function _burn(uint256 tokenId) internal override(ERC721URIStorageUpgradeable, ERC721Upgradeable) {
        require(_nftInfos[tokenId].sharing, "burn:tokenId already sharing");
        ERC721Upgradeable._burn(tokenId);
        ERC721URIStorageUpgradeable._burn(tokenId);
        delete _nftInfos[tokenId];
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * modify Token URI On IPFS by TokenId
     */
    function _setTokenURI(uint256 tokenId, string memory nftLink) internal virtual override {
        ERC721URIStorageUpgradeable._setTokenURI(tokenId, nftLink);
        _nftInfos[tokenId].nftLink = nftLink;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) {
        require(!_exists(tokenId) || !_nftInfos[tokenId].pending, "transfer:the status must not pending");
        _nftInfos[tokenId].ownerAddress = to;
        super._beforeTokenTransfer(from, to, tokenId);
    }

}
