import UIKit

final class DetailViewController: UIViewController {
    // Bug: this outlet was renamed from `titleLabel` to `headlineLabel`, but DetailView.xib's connection
    // still points at the old name `titleLabel` — the connection is now dangling.
    @IBOutlet weak var headlineLabel: UILabel!
}
