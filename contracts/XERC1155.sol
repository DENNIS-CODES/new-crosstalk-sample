// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0 <0.9.0;

import "@routerprotocol/evm-gateway-contracts/contracts/IDapp.sol";
import "@routerprotocol/evm-gateway-contracts/contracts/IGateway.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title XERC1155
/// @author Yashika Goyal
/// @notice A cross-chain ERC-1155 smart contract to demonstrate how one can create
/// cross-chain NFT contracts using Router CrossTalk.
contract XERC1155 is ERC1155, IDapp {
  // address of the owner
  address public owner;

  // address of the gateway contract
  IGateway public gatewayContract;

  // gas limit required to handle cross-chain request on the destination chain
  uint64 public _destGasLimit;

  // chain type + chain id => address of our contract in bytes
  mapping(string => bytes) public ourContractOnChains;

  bytes public _requestSender;
  string public _srcChainId;
  uint256 public _requestIdentifier;

  // transfer params struct where we specify which NFTs should be transferred to
  // the destination chain and to which address
  struct TransferParams {
    uint256[] nftIds;
    uint256[] nftAmounts;
    bytes nftData;
    bytes recipient;
  }

  constructor(
    string memory _uri,
    address payable gatewayAddress
  ) ERC1155(_uri) {
    gatewayContract = IGateway(gatewayAddress);
    owner = msg.sender;

    // minting ourselves some NFTs so that we can test out the contracts
    _mint(msg.sender, 1, 10, "");

    //gatewayContract.setDappMetadata(feePayerAddress);
  }

  /// @notice function to set the fee payer address on Router Chain.
  /// @param feePayerAddress address of the fee payer on Router Chain.
  function setDappMetadata(string memory feePayerAddress) external {
    require(msg.sender == owner, "only owner");
    gatewayContract.setDappMetadata(feePayerAddress);
  }

  /// @notice function to set the Router Gateway Contract.
  /// @param gateway address of the gateway contract.
  function setGateway(address gateway) external {
    require(msg.sender == owner, "only owner");
    gatewayContract = IGateway(gateway);
  }

  function mint(
    address account,
    uint256[] memory nftIds,
    uint256[] memory amounts,
    bytes memory nftData
  ) external {
    require(msg.sender == owner, "only owner");
    _mintBatch(account, nftIds, amounts, nftData);
  }

  /// @notice function to set the address of our NFT contracts on different chains.
  /// This will help in access control when a cross-chain request is received.
  /// @param chainId chain Id of the destination chain in string.
  /// @param contractAddress address of the NFT contract on the destination chain.
  function setContractOnChain(
    string memory chainId,
    address contractAddress
  ) external {
    require(msg.sender == owner, "only owner");
    ourContractOnChains[chainId] = toBytes(contractAddress);
  }

  /// @notice function to generate a cross-chain NFT transfer request.
  /// @param routeAmount Amount of route tokens to be sent
  /// @param routeRecipient Recipient of Route on destination chain
  /// @param destChainId chain ID of the destination chain in string.
  /// @param transferParams transfer params struct.
  /// @param requestMetadata abi-encoded metadata according to source and destination chains
  function transferCrossChain(
    uint256 routeAmount,
    bytes memory routeRecipient,
    string memory destChainId,
    TransferParams memory transferParams,
    bytes memory requestMetadata
  ) public payable {
    require(
      keccak256(ourContractOnChains[destChainId]) !=
        keccak256(toBytes(address(0))),
      "contract on dest not set"
    );

    // burning the NFTs from the address of the user calling _burnBatch function
    _burnBatch(msg.sender, transferParams.nftIds, transferParams.nftAmounts);

    // sending the transfer params struct to the destination chain as payload.
    bytes memory packet = abi.encode(transferParams);
    bytes memory requestPacket = abi.encode(
      ourContractOnChains[destChainId],
      packet
    );

    gatewayContract.iSend{ value: msg.value }(
      1,
      routeAmount,
      routeRecipient,
      destChainId,
      requestMetadata,
      requestPacket
    );
  }

  /// @notice function to get the request metadata to be used while initiating cross-chain request
  /// @return requestMetadata abi-encoded metadata according to source and destination chains
  function getRequestMetadata(
    uint64 destGasLimit,
    uint64 destGasPrice,
    uint64 ackGasLimit,
    uint64 ackGasPrice,
    uint128 relayerFees,
    uint8 ackType,
    bool isReadCall,
    bytes memory asmAddress
  ) public pure returns (bytes memory) {
    bytes memory requestMetadata = abi.encodePacked(
      destGasLimit,
      destGasPrice,
      ackGasLimit,
      ackGasPrice,
      relayerFees,
      ackType,
      isReadCall,
      asmAddress
    );
    return requestMetadata;
  }

  /// @notice function to handle the cross-chain request received from some other chain.
  /// @param requestSender address of the contract on source chain that initiated the request.
  /// @param packet the payload sent by the source chain contract when the request was created.
  /// @param srcChainId chain ID of the source chain in string.
  function iReceive(
    bytes memory requestSender,
    bytes memory packet,
    string memory srcChainId
  ) external returns (bytes memory) {
    require(msg.sender == address(gatewayContract), "only gateway");
    // decoding our payload
    TransferParams memory transferParams = abi.decode(packet, (TransferParams));
    _requestSender = requestSender;
    _srcChainId = srcChainId;
    _mintBatch(
      toAddress(transferParams.recipient),
      transferParams.nftIds,
      transferParams.nftAmounts,
      transferParams.nftData
    );

    return "";
  }

  /// @notice function to handle the acknowledgement received from the destination chain
  /// back on the source chain.
  /// @param requestIdentifier event nonce which is received when we create a cross-chain request
  /// We can use it to keep a mapping of which nonces have been executed and which did not.
  /// @param execFlag a boolean value suggesting whether the call was successfully
  /// executed on the destination chain.
  /// @param execData returning the data returned from the handleRequestFromSource
  /// function of the destination chain.
  function iAck(
    uint256 requestIdentifier,
    bool execFlag,
    bytes memory execData
  ) external {}

  /// @notice function to convert type address into type bytes.
  /// @param a address to be converted
  /// @return b bytes pertaining to the address
  function toBytes(address a) public pure returns (bytes memory b) {
    assembly {
      let m := mload(0x40)
      a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
      mstore(0x40, add(m, 52))
      b := m
    }
  }

  /// @notice Function to convert bytes to address
  /// @param _bytes bytes to be converted
  /// @return addr address pertaining to the bytes
  function toAddress(bytes memory _bytes) internal pure returns (address addr) {
    bytes20 srcTokenAddress;
    assembly {
      srcTokenAddress := mload(add(_bytes, 0x20))
    }
    addr = address(srcTokenAddress);
  }
}
