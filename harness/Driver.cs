// SPDX-License-Identifier: GPL-2.0-or-later
// Headless driver for the C# 2.01 game logic. Emits JSON fixtures consumed by the Swift tests (PRD §8.4).
// Usage: ParsecHarness <command> <outDir>
//   rng     — System.Random vectors (seeded)
//   galaxy  — universe/crew/commander/prices for several seeds and difficulties
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace Fryz.Apps.SpaceTrader
{
	public static class HarnessDriver
	{
		static readonly JsonSerializerOptions Json = new JsonSerializerOptions { WriteIndented = false };

		public static int Main(string[] args)
		{
			if (args.Length < 2) { Console.Error.WriteLine("usage: ParsecHarness <rng|galaxy|all> <outDir>"); return 2; }
			string cmd = args[0], dir = args[1];
			Directory.CreateDirectory(dir);
			if (cmd == "rng" || cmd == "all") Write(dir, "rng-dotnet.json", Rng());
			if (cmd == "galaxy" || cmd == "all") Write(dir, "galaxy-windows201.json", Galaxies());
			if (cmd == "market" || cmd == "all") Write(dir, "market-windows201.json", MarketSteps());
			return 0;
		}

		static void Write(string dir, string name, object o)
		{
			File.WriteAllText(Path.Combine(dir, name), JsonSerializer.Serialize(o, Json) + "\n");
			Console.WriteLine("wrote " + name);
		}

		public static void SeedRandom(int seed)
		{
			FieldInfo f = typeof(Functions).GetField("rand", BindingFlags.NonPublic | BindingFlags.Static);
			f.SetValue(null, new Random(seed));
		}

		static object Rng()
		{
			var list = new List<object>();
			foreach (int seed in new[] { 0, 1, 42, 12345, 2147483647, -2147483648, -42 })
			{
				var r1 = new Random(seed); var next = new List<int>(); for (int i = 0; i < 20; i++) next.Add(r1.Next());
				var r2 = new Random(seed); var below = new List<int>(); foreach (int m in new[] { 1, 2, 5, 6, 10, 17, 100, 1000, 0, 154, 110, 13 }) below.Add(r2.Next(0, m));
				var r3 = new Random(seed); var range = new List<int>(); foreach (var p in new[] { (-12, 13), (1, 8), (1, 13), (5, 5), (-4, 5), (9, 14) }) range.Add(r3.Next(p.Item1, p.Item2));
				var r4 = new Random(seed); var doubles = new List<double>(); for (int i = 0; i < 5; i++) doubles.Add(r4.NextDouble());
				list.Add(new { seed, next, belowMax = new[] { 1, 2, 5, 6, 10, 17, 100, 1000, 0, 154, 110, 13 }, below, rangePairs = new[] { "-12,13", "1,8", "1,13", "5,5", "-4,5", "9,14" }, range, doubles });
			}
			return list;
		}

		static object Galaxies()
		{
			var list = new List<object>();
			foreach (int seed in new[] { 0, 1, 2, 3, 42, 1000, 12345 })
				foreach (Difficulty d in new[] { Difficulty.Beginner, Difficulty.Normal, Difficulty.Impossible })
					list.Add(GalaxySnapshot(seed, d));
			return list;
		}

		public static object GalaxySnapshot(int seed, Difficulty d)
		{
			SeedRandom(seed);
			var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
			var systems = new List<object>();
			foreach (StarSystem s in game.Universe)
			{
				var qty = new int[10];
				for (int i = 0; i < 10; i++) qty[i] = s.TradeItems[i];
				systems.Add(new
				{
					id = (int)s.Id, x = s.X, y = s.Y, size = (int)s.Size, tech = (int)s.TechLevel, politics = (int)s.PoliticalSystemType,
					pressure = (int)s.SystemPressure, resource = (int)SpecialResourceRaw(s), special = (int)s.SpecialEventType,
					shipyard = (int)s.ShipyardId, quantities = qty, countdown = s.CountDown, visited = s.Visited
				});
			}
			var crew = new List<object>();
			foreach (CrewMember c in game.Mercenaries)
				crew.Add(new { id = (int)c.Id, skills = c.Skills, system = c.CurrentSystemId == StarSystemId.NA ? -1 : (int)c.CurrentSystemId });
			var cmdr = game.Commander;
			return new
			{
				seed, difficulty = (int)d, wormholes = game.Wormholes, systems, crew,
				commander = new { system = (int)cmdr.CurrentSystemId, cash = cmdr.Cash, ship = (int)cmdr.Ship.Type, fuel = cmdr.Ship.Fuel, hull = cmdr.Ship.Hull },
				buyPrices = game.PriceCargoBuy, sellPrices = game.PriceCargoSell
			};
		}

		/// Restock/pressure/price evolution: after construction, set countdowns, mark some systems visited,
		/// choose a warp system and run ArrivalUpdatePressuresAndQuantities + CalculatePrices(warp) several times.
		static object MarketSteps()
		{
			var list = new List<object>();
			MethodInfo arrive = typeof(Game).GetMethod("ArrivalUpdatePressuresAndQuantities", BindingFlags.NonPublic | BindingFlags.Instance);
			MethodInfo calc = typeof(Game).GetMethod("CalculatePrices", BindingFlags.NonPublic | BindingFlags.Instance);
			foreach (int seed in new[] { 7, 42 })
			{
				foreach (Difficulty d in new[] { Difficulty.Easy, Difficulty.Hard })
				{
					SeedRandom(seed);
					var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
					var steps = new List<object>();
					for (int step = 0; step < 6; step++)
					{
						int warp = (step * 37 + seed) % game.Universe.Length;
						for (int i = 0; i < game.Universe.Length; i += 3) game.Universe[i].CountDown = (i + step) % 7;
						for (int i = 0; i < game.Universe.Length; i += 5) game.Universe[i].Visited = true;
						game.Commander.PoliceRecordScore = step % 2 == 0 ? 0 : -10;
						typeof(Game).GetField("_warpSystemId", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(game, (StarSystemId)warp);
						arrive.Invoke(game, null);
						calc.Invoke(game, new object[] { game.Universe[warp] });
						var qty = new List<int[]>(); var press = new List<int>(); var cd = new List<int>();
						foreach (StarSystem sys in game.Universe)
						{
							var q = new int[10]; for (int i = 0; i < 10; i++) q[i] = sys.TradeItems[i];
							qty.Add(q); press.Add((int)sys.SystemPressure); cd.Add(sys.CountDown);
						}
						steps.Add(new { warp, record = game.Commander.PoliceRecordScore, quantities = qty, pressures = press, countdowns = cd,
							buyPrices = (int[])game.PriceCargoBuy.Clone(), sellPrices = (int[])game.PriceCargoSell.Clone() });
					}
					list.Add(new { seed, difficulty = (int)d, steps });
				}
			}
			return list;
		}

		/// StarSystem.SpecialResource hides the value until visited; read the backing field instead.
		static SpecialResource SpecialResourceRaw(StarSystem s)
		{
			FieldInfo f = typeof(StarSystem).GetField("_specialResource", BindingFlags.NonPublic | BindingFlags.Instance);
			return (SpecialResource)f.GetValue(s);
		}
	}
}
