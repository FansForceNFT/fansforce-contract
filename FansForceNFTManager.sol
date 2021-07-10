// SPDX-License-Identifier: GPL-3

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FansForceNFTManager is TransparentUpgradeableProxy {

    constructor(address _logic, address admin_, bytes memory _data)
    TransparentUpgradeableProxy(_logic, admin_, _data){}

}
