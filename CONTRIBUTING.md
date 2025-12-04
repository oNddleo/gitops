# Contributing Guidelines

Thank you for considering contributing to this project! Your help is greatly appreciated.

## How to Contribute

1.  **Fork the Repository**: Start by forking the `gitops` repository to your GitHub account.
2.  **Clone Your Fork**: Clone your forked repository to your local machine:
    ```bash
    git clone https://github.com/YOUR_USERNAME/gitops.git
    cd gitops
    ```
3.  **Create a New Branch**: Create a new branch for your feature or bug fix:
    ```bash
    git checkout -b feature/your-feature-name
    # or
    git checkout -b bugfix/issue-description
    ```
    Please use descriptive branch names.

4.  **Make Your Changes**:
    *   Ensure your code adheres to the existing coding style and conventions.
    *   Add or update documentation as necessary (especially in the `docs/` directory).
    *   If you're fixing a bug, include a test that reproduces the bug before your fix and passes after.
    *   If you're adding a new feature, ensure it is covered by appropriate tests.

5.  **Test Your Changes**:
    Run any relevant tests or verification steps (e.g., `helm lint`, `kubectl apply --dry-run`).
    Ensure the `deploy.sh` script still works as expected if your changes affect the core deployment flow.

6.  **Commit Your Changes**: Commit your changes with a clear and concise message. Follow conventional commit guidelines if applicable.
    ```bash
    git commit -m "feat: Add new awesome feature"
    # or
    git commit -m "fix: Resolve issue with Linkerd certificates"
    ```

7.  **Push to Your Fork**: Push your branch to your forked repository:
    ```bash
    git push origin feature/your-feature-name
    ```

8.  **Create a Pull Request (PR)**:
    *   Go to your fork on GitHub and open a new Pull Request.
    *   Provide a clear title and description for your PR. Explain the problem it solves or the feature it adds, and any relevant context.
    *   Reference any related issues (e.g., "Fixes #123" or "Closes #456").
    *   Request a review from the maintainers.

## Code of Conduct

Please note that this project is released with a Contributor Code of Conduct. By participating in this project, you agree to abide by its terms.

## Reporting Bugs

If you find a bug, please open an issue on GitHub. Include:
*   A clear and concise description of the bug.
*   Steps to reproduce the behavior.
*   Expected behavior.
*   Screenshots (if applicable).
*   Your environment details (OS, Kubernetes version, etc.).

## Feature Requests

If you have a suggestion for a new feature, please open an issue on GitHub. Include:
*   A clear and concise description of the feature.
*   Why this feature would be useful.
*   Any potential alternatives you've considered.

## Licensing

By contributing, you agree that your contributions will be licensed under the MIT License.
