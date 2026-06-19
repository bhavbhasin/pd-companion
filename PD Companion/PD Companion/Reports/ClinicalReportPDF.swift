import UIKit

// MARK: - Clinical report PDF
//
// Renders a focused, branded clinical summary for one insight to a real PDF the
// user can AirDrop / email / print and bring to an appointment. This is the native
// reproduction of the locked `analysis/make_clinical_pdf.py` layout — text first,
// statistics demoted, with an n-of-1 safety footer.
//
// CHARTS are deliberately deferred: drawing the wearing-off / dose-response curves
// natively needs the engine to expose averaged trajectories (a separate port). The
// text content is the substance; charts are the next iteration.

private let kPage = CGSize(width: 612, height: 792)        // US Letter
private let kMargin: CGFloat = 48
private let kBlue = UIColor(red: 0.290, green: 0.549, blue: 0.839, alpha: 1)   // brand #4A8CD6
private let kInk = UIColor(red: 0.102, green: 0.114, blue: 0.133, alpha: 1)    // #1A1D22
private let kGray = UIColor(white: 0.42, alpha: 1)

enum ClinicalReportPDF {

    /// Build a multi-insight clinical report PDF, returning a temp-file URL or nil.
    static func generate(insights: [Insight]) -> URL? {
        guard !insights.isEmpty else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: kPage))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kampa-Report.pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var c = Cursor(ctx: ctx)
                c.y = kMargin

                drawHeader(&c)
                c.space(20)

                let days = insights.map(\.evidenceDays).max() ?? 0
                let intro = "A plain-language summary of patterns Kampa detected from passive Apple Watch monitoring over \(days) days, prepared for discussion with your care team. One person's own data (n-of-1) — not a diagnosis or a treatment recommendation."
                c.text(intro, .systemFont(ofSize: 11), kInk)
                c.space(16)

                c.label("AT A GLANCE")
                for i in insights { c.glance(i.title, i.summary) }
                c.space(14)

                for i in insights {
                    c.section(i.title)
                    c.label("THE PATTERN")
                    c.text("\(i.summary) \(i.finding)", .systemFont(ofSize: 12), kInk)
                    if let clinical = i.clinical {
                        c.space(12)
                        c.label("WHAT YOUR NEUROLOGIST MIGHT CONSIDER")
                        c.text(clinical.whatTheyMightConsider, .systemFont(ofSize: 12), kInk)
                        c.space(12)
                        c.label("BRING THIS TO YOUR APPOINTMENT")
                        for item in clinical.bringThisData { c.bullet(item) }
                    }
                    c.space(18)
                }

                c.label("METHODS & PROVENANCE")
                c.text(methodsText, .systemFont(ofSize: 10), kGray)
                c.space(10)
                c.text(safetyText, .italicSystemFont(ofSize: 9), kGray)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: Header

    private static func drawHeader(_ c: inout Cursor) {
        let big = UIFont.systemFont(ofSize: 24, weight: .semibold)
        let wordmark = NSMutableAttributedString()
        wordmark.append(NSAttributedString(string: "k", attributes: [.font: big, .foregroundColor: kInk]))
        wordmark.append(NSAttributedString(string: "ā", attributes: [.font: big, .foregroundColor: kBlue]))
        wordmark.append(NSAttributedString(string: "mpa", attributes: [.font: big, .foregroundColor: kInk]))
        wordmark.draw(at: CGPoint(x: kMargin, y: c.y))

        let sub = NSAttributedString(string: "Clinical Summary Report", attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: kBlue])
        let date = NSAttributedString(string: "Generated \(formattedDate())", attributes: [
            .font: UIFont.systemFont(ofSize: 9), .foregroundColor: kGray])
        let subSize = sub.size(), dateSize = date.size()
        sub.draw(at: CGPoint(x: kPage.width - kMargin - subSize.width, y: c.y + 3))
        date.draw(at: CGPoint(x: kPage.width - kMargin - dateSize.width, y: c.y + 3 + subSize.height + 2))

        c.y += 36
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: kMargin, y: c.y))
        rule.addLine(to: CGPoint(x: kPage.width - kMargin, y: c.y))
        UIColor(white: 0.88, alpha: 1).setStroke()
        rule.lineWidth = 1
        rule.stroke()
    }

    private static func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: Date())
    }

    private static let methodsText =
        "Tremor and dyskinesia are measured passively by Apple Watch using Apple's Movement "
        + "Disorder API (~1 reading/minute while worn), on a 0–4 severity scale (lower tremor = "
        + "better ON). Patterns are found with deterministic statistics on the patient's own "
        + "timeline — event-aligned dose-response and Kaplan–Meier ON-duration — no machine "
        + "learning and no population model. Every figure traces to the underlying readings."

    private static let safetyText =
        "One person's own data (n-of-1), shared for discussion — not a diagnosis or a treatment "
        + "recommendation. Do not change any medication without your neurologist."
}

// MARK: - Tiny paginating text cursor

private struct Cursor {
    let ctx: UIGraphicsPDFRendererContext
    var y: CGFloat = 0
    private let x = kMargin
    private var width: CGFloat { kPage.width - kMargin * 2 }

    mutating func space(_ h: CGFloat) { y += h }

    /// Start a new page if `h` more points won't fit in the current one.
    private mutating func ensure(_ h: CGFloat) {
        if y + h > kPage.height - kMargin {
            ctx.beginPage()
            y = kMargin
        }
    }

    mutating func text(_ s: String, _ font: UIFont, _ color: UIColor) {
        draw(NSAttributedString(string: s, attributes: paragraph(font, color)), gap: 0)
    }

    mutating func label(_ s: String) {
        draw(NSAttributedString(string: s, attributes: [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: kGray, .kern: 0.5]), gap: 5)
    }

    /// A bold section header for one finding.
    mutating func section(_ title: String) {
        space(4)
        draw(NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: kInk]), gap: 6)
    }

    /// An "at a glance" row: chevroned title + indented one-line summary.
    mutating func glance(_ title: String, _ sub: String) {
        draw(NSAttributedString(string: "›  \(title)", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: kInk]), gap: 1)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        para.firstLineHeadIndent = 14
        para.headIndent = 14
        draw(NSAttributedString(string: sub, attributes: [
            .font: UIFont.systemFont(ofSize: 10), .foregroundColor: kGray, .paragraphStyle: para]), gap: 8)
    }

    mutating func bullet(_ s: String) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        para.headIndent = 12
        draw(NSAttributedString(string: "•  \(s)", attributes: [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: kInk, .paragraphStyle: para]),
             gap: 4)
    }

    private mutating func paragraph(_ font: UIFont, _ color: UIColor) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        return [.font: font, .foregroundColor: color, .paragraphStyle: para]
    }

    private mutating func draw(_ attr: NSAttributedString, gap: CGFloat) {
        let rect = attr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        ensure(rect.height)
        attr.draw(in: CGRect(x: x, y: y, width: width, height: ceil(rect.height)))
        y += ceil(rect.height) + gap
    }
}
