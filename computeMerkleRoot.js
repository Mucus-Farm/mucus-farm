const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

let addresses = [
  "0x0000000000000000000000000000000000000000",
  "0x0000000000000000000000000000000000000001",
  "0x0000000000000000000000000000000000000002",
  "0x0000000000000000000000000000000000000003",
];
let leaves = addresses.map((addr) => keccak256(addr));
let merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
let rootHash = merkleTree.getRoot().toString("hex");

console.log(merkleTree.toString());
console.log(rootHash);

console.log(rootHash);
