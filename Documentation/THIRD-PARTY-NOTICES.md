# Third-party notices

## Apple Device Management Client Schema

The generated Restrictions catalogue is derived from schema data in Apple's `apple/device-management` repository.

- Source: <https://github.com/apple/device-management>
- Licence: MIT
- Local generator: `Tools/GenerateRestrictionCatalogue.rb`
- Bundled schema target: iOS/iPadOS 26.4

The generated catalogue contains payload key names, titles, availability metadata and condensed descriptions. Regeneration must be reviewed and tested before a newer schema snapshot is accepted.

## MLX Swift and MLX Swift LM

The optional enhanced on-device model is loaded and run through Apple's open-source MLX projects.

- Sources: <https://github.com/ml-explore/mlx-swift> and <https://github.com/ml-explore/mlx-swift-lm>
- Licence: MIT
- Pinned Swift LM version: 3.31.4

## Qwen3.5 4B MLX 4-bit

The application can download an MLX conversion of Qwen3.5 4B when the user explicitly enables the enhanced model.

- Model: <https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit>
- Source model: <https://huggingface.co/Qwen/Qwen3.5-4B>
- Licence: Apache 2.0
- Pinned model revision: `32f3e8ecf65426fc3306969496342d504bfa13f3`
- Approximate disk download: 3 GB

The model is not embedded in the source repository or application bundle. Review and redistribute its licence and notice files if a future installer bundles the weights.

## Hugging Face Swift libraries

Model download and tokenizer loading use the open-source `swift-huggingface` and `swift-transformers` packages. Their exact versions and transitive dependencies are recorded in `Package.resolved`. No Hugging Face account or inference service is required for this public model.
