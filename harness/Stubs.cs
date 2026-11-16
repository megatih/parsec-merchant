// SPDX-License-Identifier: GPL-2.0-or-later
// Minimal stand-ins for WinForms / GDI+ types referenced by the C# 2.01 game-logic files, so the logic can run
// headless on macOS. Dialogs never render; answers come from Harness.Policy.
using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace System.Windows.Forms
{
	public interface IWin32Window { }
	public enum DialogResult { None, OK, Cancel, Abort, Retry, Ignore, Yes, No }
	public class ImageList
	{
		public System.Drawing.Image[] Images = new System.Drawing.Image[80];
	}
	public class Form : IWin32Window
	{
		public virtual DialogResult ShowDialog(IWin32Window owner) => DialogResult.OK;
	}
}

namespace System.Drawing
{
	public enum GraphicsUnit { Pixel }
	public class Image
	{
		public int Width = 64, Height = 52;
		public static Image FromFile(string f) => new Image();
	}
	public class Bitmap : Image
	{
		public Bitmap() { }
		public Bitmap(Image i) { }
		public Bitmap(string s) { }
		public Color GetPixel(int x, int y) => Color.White;
	}
	public class Graphics
	{
		public void Clear(Color c) { }
		public void DrawImage(Image i, int x, int y, Rectangle r, GraphicsUnit u) { }
		public void DrawLine(Pen p, int a, int b, int c, int d) { }
	}
	public class Pen
	{
		public Pen(Color c) { }
		public Pen(Color c, float w) { }
	}
}

namespace Fryz.Apps.SpaceTrader
{
	/// Answer policy for dialogs raised by the game logic.
	public static class Harness
	{
		public static Func<AlertType, DialogResult> Policy = _ => DialogResult.Yes;
		public static List<string> Alerts = new List<string>();
		public static int CargoAmount = 0;
	}

	public class SpaceTrader : IWin32Window
	{
		public ImageList ShipImages = new ImageList();
		public ImageList EquipmentImages = new ImageList();
		public System.Drawing.Image[] CustomShipImages = new System.Drawing.Image[4];
		public void UpdateAll() { }
		public void UpdateStatusBar() { }
	}

	public class FormAlert : Form
	{
		public static DialogResult Alert(AlertType type, IWin32Window owner) => Record(type);
		public static DialogResult Alert(AlertType type, IWin32Window owner, string var1) => Record(type);
		public static DialogResult Alert(AlertType type, IWin32Window owner, string var1, string var2) => Record(type);
		public static DialogResult Alert(AlertType type, IWin32Window owner, string var1, string var2, string var3) => Record(type);
		public static DialogResult Alert(AlertType type, IWin32Window owner, string[] args) => Record(type);
		static DialogResult Record(AlertType t) { Harness.Alerts.Add(t.ToString()); return Harness.Policy(t); }
	}

	public class FormEncounter : Form
	{
		public EncounterResult Result = EncounterResult.Normal;
	}

	public class FormPlunder : Form { }
	public class FormJettison : Form { }

	public class FormCargoBuy : Form
	{
		public FormCargoBuy(int item, int maxAmount, CargoBuyOp op) { Amount = Math.Min(maxAmount, Harness.CargoAmount); }
		public int Amount;
	}

	public class FormCargoSell : Form
	{
		public FormCargoSell(int item, int maxAmount, CargoSellOp op, int price) { Amount = Math.Min(maxAmount, Harness.CargoAmount); }
		public int Amount;
	}
}
