// SPDX-License-Identifier: GPL-3

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";


contract NFTShareTemp is Initializable, ContextUpgradeable, AccessControlEnumerableUpgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    address private _nftContract;
    uint256 private _tokenId;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    function initialize(string memory name, string memory symbol, uint8 decimal, address nftContractAddr,
        uint256 tokenId) public virtual initializer {
        require(nftContractAddr != address(0), "nftContractAddr invalid");
        __ERC20Share_init(name, symbol, nftContractAddr);
        _decimals = decimal;
        _nftContract = nftContractAddr;
        _tokenId = tokenId;
    }

    /**
     * Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "NFTShareTemp: must have minter role to mint");
        _mint(to, amount);
    }

    /**
     * Pauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "NFTShareTemp: must have pauser role to pause");
        _pause();
    }

    /**
     * Unpauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "NFTShareTemp: must have pauser role to unpause");
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function nftContract() public view virtual returns (address) {
        return _nftContract;
    }

    function nftTokenId() public view virtual returns (uint256) {
        return _tokenId;
    }

    function __ERC20Share_init(string memory name, string memory symbol, address owner) internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __ERC20_init_unchained(name, symbol);
        __ERC20Burnable_init_unchained();
        __Pausable_init_unchained();
        __ERC20Pausable_init_unchained();
        __ERC20Other_init_unchained(owner);
    }

    function __ERC20Other_init_unchained(address owner) internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);
        _setupRole(PAUSER_ROLE, owner);
    }

}
