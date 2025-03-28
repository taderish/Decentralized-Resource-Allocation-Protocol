# Decentralized Resource Allocation Protocol

This repository contains a decentralized protocol designed to manage and track resource allocation on the blockchain. The protocol is implemented using Clarity, a language for writing smart contracts on the Stacks blockchain, enabling trustless and secure distribution of resources.

## Features

- **Impact Allocation**: Launch and manage resource allocations to recipients over multiple stages with milestone tracking.
- **Stage Validation**: Verify and approve resource releases in stages, ensuring that funds are allocated progressively.
- **Refund Mechanism**: Allow for refunds to the initiator of an allocation if necessary.
- **Allocation Termination**: Terminate allocations early with proper fund return.
- **Circuit Breaker**: Prevent further actions if the protocol enters a cooling-down state.
- **Multi-Recipient Allocation**: Split resources among multiple recipients with configurable percentage distributions.
- **Admin Controls**: The protocol includes various administrative controls such as pausing the system, extending allocation expiration, and managing recipient whitelists.

## Protocol Overview

The system consists of the following core components:

1. **Impact Allocations**: Each allocation has a unique ID, initiator, recipient, total resource amount, status, and milestone tracking. The allocation progresses through various stages, and resources are distributed accordingly.

2. **Resource Split Allocations**: Allows the allocation of resources to multiple recipients, where each recipient receives a specified percentage of the total resources.

3. **Circuit Breaker**: A mechanism for protecting the protocol during certain critical failure conditions by enforcing a cooldown period.

4. **Expiration Extension**: Allocations can be extended by a specified number of blocks if necessary.

5. **Recipient Management**: The protocol allows administrators to manage the whitelist of approved recipients.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-username>/Decentralized-Resource-Allocation-Protocol.git
   cd Decentralized-Resource-Allocation-Protocol
   ```

2. Set up your environment:
   - Ensure you have [Stacks CLI](https://docs.stacks.co/build-apps/clarity-cli) installed to interact with the Clarity contracts.
   - If necessary, set up an environment for developing and deploying Clarity smart contracts.

## Deployment

1. Deploy the contracts on the Stacks blockchain using the Stacks CLI.
2. Interact with the contracts using a Stacks wallet or through the provided functions.

## Contract Functions

Here is a summary of the key contract functions:

- `launch-impact-allocation`: Initializes an impact allocation, transferring resources to the protocol and allocating them to a recipient based on milestone stages.
- `validate-allocation-stage`: Validates and releases a stage's resource to the recipient.
- `refund-initiator`: Allows the initiator to get a refund of their resources if the allocation has expired.
- `terminate-allocation`: Terminates an allocation early and refunds the remaining resource to the initiator.
- `set-protocol-pause-state`: Pauses or unpauses the protocol (admin control).
- `extend-allocation-expiration`: Extends the expiration of an allocation.

## Security

The protocol uses various security mechanisms to ensure that the resource distribution is trustworthy:

- **Validation checks**: Ensures the allocation data is valid, including checking that recipients are not the same as the sender, and that amounts and allocation IDs are valid.
- **Authorization checks**: Ensures that only the protocol administrator can perform critical functions like pausing the protocol or refunding the initiator.
- **Fund Protection**: The protocol protects resources through stage-by-stage releases and a circuit breaker mechanism for protection during exceptional conditions.

## Contributing

Contributions to the protocol are welcome! Please fork the repository and submit a pull request with your changes. Ensure that all code is well-documented, and any changes are thoroughly tested.

### Steps to contribute:
1. Fork the repository.
2. Create a new branch (`git checkout -b feature-name`).
3. Make your changes.
4. Commit your changes (`git commit -am 'Add feature'`).
5. Push to the branch (`git push origin feature-name`).
6. Open a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
