// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOrbitalOctopus {
    function mint(address account, uint256 amount) external;
    // Add other functions you want to interact with here

    function approve(address spender, uint256 amount) external;

    function transfer(address recipient, uint256 amount) external returns (bool);
    
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

}
