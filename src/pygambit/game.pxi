#
# This file is part of Gambit
# Copyright (c) 1994-2023, The Gambit Project (http://www.gambit-project.org)
#
# FILE: src/python/gambit/lib/game.pxi
# Cython wrapper for games
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
import itertools
import pathlib

import numpy as np

import pygambit.gte
import pygambit.gameiter

@cython.cclass
class Outcomes(Collection):
    """Represents a collection of outcomes in a game."""
    game = cython.declare(c_Game)

    def __len__(self):
        """The number of outcomes in the game."""
        return self.game.deref().NumOutcomes()

    def __getitem__(self, outc):
        if not isinstance(outc, int):
            return Collection.__getitem__(self, outc)
        c = Outcome()
        c.outcome = self.game.deref().GetOutcome(outc+1)
        return c

    def add(self, label=""):
        """Add a new outcome to the game."""
        c = Outcome()
        c.outcome = self.game.deref().NewOutcome()
        if label != "":
            c.label = str(label)
        return c


@cython.cclass
class Players(Collection):
    """Represents a collection of players in a game."""
    game = cython.declare(c_Game)
    restriction = cython.declare(StrategicRestriction)

    def __len__(self):
        """Returns the number of players in the game."""
        return self.game.deref().NumPlayers()

    def __getitem__(self, pl):
        if not isinstance(pl, int):
            return Collection.__getitem__(self, pl)
        p = Player()
        p.player = self.game.deref().GetPlayer(pl+1)
        if self.restriction is not None:
            p.restriction = self.restriction
        return p

    def add(self, label="") -> Player:
        """Adds a new player to the game."""
        if self.restriction is not None:
            raise UndefinedOperationError("Changing objects in a restriction is not supported")
        p = Player()
        p.player = self.game.deref().NewPlayer()
        if label != "":
            p.label = str(label)
        return p

    @property
    def chance(self) -> Player:
        """Returns the chance player associated with the game."""
        p = Player()
        p.player = self.game.deref().GetChance()
        p.restriction = self.restriction
        return p


@cython.cclass
class GameActions(Collection):
    """Represents a collection of actions in a game."""
    game = cython.declare(c_Game)

    def __len__(self):
        return self.game.deref().BehavProfileLength()

    def __getitem__(self, action):
        if not isinstance(action, int):
            return Collection.__getitem__(self, action)
        a = Action()
        a.action = self.game.deref().GetAction(action+1)
        return a


@cython.cclass
class GameInfosets(Collection):
    """Represents a collection of infosets in a game."""
    game = cython.declare(c_Game)

    def __len__(self):
        num_infosets = self.game.deref().NumInfosets()
        size = num_infosets.Length()
        n = 0
        for i in range(1, size+1):
            n += num_infosets.getitem(i)
        return n

    def __getitem__(self, infoset):
        if not isinstance(infoset, int):
            return Collection.__getitem__(self, infoset)
        i = Infoset()
        i.infoset = self.game.deref().GetInfoset(infoset+1)
        return i


@cython.cclass
class GameStrategies(Collection):
    """Represents a collection of strategies in a game."""
    game = cython.declare(c_Game)

    def __len__(self):
        return self.game.deref().MixedProfileLength()

    def __getitem__(self, st):
        if not isinstance(st, int):
            return Collection.__getitem__(self, st)
        s = Strategy()
        s.strategy = self.game.deref().GetStrategy(st+1)
        return s


@cython.cclass
class Game:
    """Represents a game, the fundamental concept in game theory.
    Games may be represented in extensive or strategic form.
    """
    game = cython.declare(c_Game)

    @classmethod
    def new_tree(cls, title: str="Untitled extensive game") -> Game:
        """Creates a new Game consisting of a trivial game tree,
        with one node, which is both root and terminal, and only the chance player.

        .. versionchanged:: 16.1.0
	        Added the ``title`` parameter.

        Parameters
        ----------
        title : str, optional
            The title of the game.  If no title is specified, "Untitled extensive game"
            is used.

        Returns
        -------
        Game
            The newly-created extensive game.
        """
        g = cython.declare(Game)
        g = cls()
        g.game = NewTree()
        g.title = title
        return g

    @classmethod
    def new_table(cls, dim, title: str="Untitled strategic game") -> Game:
        """Creates a new Game with a strategic representation.

        .. versionchanged:: 16.1.0
            Added the ``title`` parameter.

        Parameters
        ----------
        dim : array-like
            A list specifying the number of strategies for each player.
        title : str, optional
            The title of the game.  If no title is specified, "Untitled strategic game"
            is used.

        Returns
        -------
        Game
            The newly-created strategic game.
        """
        g = cython.declare(Game)
        cdef Array[int] *d
        d = new Array[int](len(dim))
        for i in range(1, len(dim)+1):
            setitem_array_int(d, i, dim[i-1])
        g = cls()
        g.game = NewTable(d)
        del d
        g.title = title
        return g

    @classmethod
    def from_arrays(cls, *arrays, title: str="Untitled strategic game") -> Game:
        """Creates a new Game with a strategic representation.

        Each entry in ``arrays`` gives the payoff matrix for the
        corresponding player.  The arrays must all have the same shape,
        and have the same number of dimensions as the total number of
        players.

        .. versionchanged:: 16.1.0
            Added the ``title`` parameter.

        Parameters
        ----------
        arrays : array-like of array-like
            The payoff matrices for the players.
        title : str, optional
            The title of the game.  If no title is specified, "Untitled strategic game"
            is used.

        Returns
        -------
        Game
            The newly-created strategic game.
        """
        g = cython.declare(Game)
        arrays = [np.array(a) for a in arrays]
        if len(set(a.shape for a in arrays)) > 1:
            raise ValueError("All specified arrays must have the same shape")
        g = Game.new_table(arrays[0].shape)
        for profile in itertools.product(
                *(range(arrays[0].shape[i]) for i in range(len(g.players)))
        ):
            for pl in range(len(g.players)):
                g[profile][pl] = arrays[pl][profile]
        g.title = title
        return g

    @classmethod
    def from_dict(cls, payoffs, title: str="Untitled strategic game") -> Game:
        """Creates a new Game with a strategic representation.

        Each entry in ``payoffs`` is a key-value pair
        giving the label and the payoff matrix for a player.
        The payoff matrices must all have the same shape,
        and have the same number of dimensions as the total number of
        players.

        Parameters
        ----------
        payoffs : dict-like mapping str to array-like
            The names and corresponding payoff matrices for the players.
        title : str, optional
            The title of the game.  If no title is specified, "Untitled strategic game"
            is used.

        Returns
        -------
        Game
            The newly-created strategic game.
        """
        g = cython.declare(Game)
        payoffs = {k: np.array(v) for k, v in payoffs.items()}
        if len(set(a.shape for a in payoffs.values())) > 1:
            raise ValueError("All specified arrays must have the same shape")
        arrays = list(payoffs.values())
        shape = arrays[0].shape
        g = Game.new_table(shape)
        for (player, label) in zip(g.players, payoffs):
            player.label = label
        for profile in itertools.product(
                *(range(shape[i]) for i in range(len(g.players)))
        ):
            for (pl, _) in enumerate(arrays):
                g[profile][pl] = arrays[pl][profile]
        g.title = title
        return g

    @classmethod
    def read_game(cls, filepath: typing.Union[str, pathlib.Path]) -> Game:
        """Constructs a game from its serialised representation in a file.

        Parameters
        ----------
        filepath : str or path object
            The path to the file containing the game representation.

        Returns
        -------
        Game
            A game constructed from the representation in the file.

        Raises
        ------
        IOError
            If the file cannot be opened or read
        ValueError
            If the contents of the file are not a valid game representation.

        See Also
        --------
        parse_game : Constructs a game from a text string.
        """
        g = cython.declare(Game)
        g = cls()
        with open(filepath, "rb") as f:
            data = f.read()
        try:
            g.game = ParseGame(data)
        except Exception as exc:
            raise ValueError(f"Parse error in game file: {exc}") from None
        return g

    @classmethod
    def parse_game(cls, text: str) -> Game:
        """Constructs a game from its serialised representation in a string
        .
        Parameters
        ----------
        text : str
            A string containing the game representation.

        Returns
        -------
        Game
            A game constructed from the representation in the string.

        Raises
        ------
        ValueError
            If the contents of the file are not a valid game representation.

        See Also
        --------
        read_game : Constructs a game from a representation in a file.
        """
        g = cython.declare(Game)
        g = cls()
        try:
            g.game = ParseGame(text.encode('ascii'))
        except Exception as exc:
            raise ValueError(f"Parse error in game file: {exc}") from None
        return g        

    def __str__(self):
        return f"<Game '{self.title}'>"

    def __repr__(self):
        return self.write()

    def _repr_html_(self):
        if self.is_tree:
            return self.write()
        else:
            return self.write('html')

    def __eq__(self, other: typing.Any) -> bool:
        return isinstance(other, Game) and self.game.deref() == cython.cast(Game, other).game.deref()

    def __ne__(self, other: typing.Any) -> bool:
        return not isinstance(other, Game) or self.game.deref() != cython.cast(Game, other).game.deref()

    def __hash__(self) -> int:
        return cython.cast(cython.long, self.game.deref())

    @property
    def is_tree(self) -> bool:
        """Returns whether a game has a tree-based representation."""
        return self.game.deref().IsTree()

    @property
    def title(self) -> str:
        """Gets or sets the title of the game.  The title of the game is
        an arbitrary string, generally intended to be short."""
        return self.game.deref().GetTitle().decode('ascii')

    @title.setter
    def title(self, value: str) -> None:
        self.game.deref().SetTitle(value.encode('ascii'))

    @property
    def comment(self) -> str:
        """Gets or sets the comment of the game.  A game's comment is
        an arbitrary string, and may be more discursive than a title."""
        return self.game.deref().GetComment().decode('ascii')

    @comment.setter
    def comment(self, value: str) -> None:
        self.game.deref().SetComment(value.encode('ascii'))

    @property
    def actions(self) -> GameActions:
        """Return the set of actions available in the game.

        Raises
        ------
        UndefinedOperationError
            If the game does not have a tree representation.
        """
        if not self.is_tree:
            raise UndefinedOperationError("Operation only defined for games with a tree representation")
        a = GameActions()
        a.game = self.game
        return a

    @property
    def infosets(self) -> GameInfosets:
        """Return the set of information sets in the game.

        Raises
        ------
        UndefinedOperationError
            If the game does not have a tree representation.
        """
        if not self.is_tree:
            raise UndefinedOperationError("Operation only defined for games with a tree representation")
        i = GameInfosets()
        i.game = self.game
        return i

    @property
    def players(self) -> Players:
        """Return the set of players in the game."""
        p = Players()
        p.game = self.game
        return p

    @property
    def strategies(self) -> GameStrategies:
        """Return the set of strategies in the game."""
        s = GameStrategies()
        s.game = self.game
        return s

    @property
    def outcomes(self) -> Outcomes:
        """Return the set of outcomes in the game."""
        c = Outcomes()
        c.game = self.game
        return c

    @property
    def contingencies(self) -> pygambit.gameiter.Contingencies:
        """Return an iterator over the contingencies in the game."""
        return pygambit.gameiter.Contingencies(self)

    @property
    def root(self) -> Node:
        """Returns the root node of the game.

        Raises
        ------
        UndefinedOperationError
            If the game does not hae a tree representation.
        """
        if not self.is_tree:
            raise UndefinedOperationError("Operation only defined for games with a tree representation")
        n = Node()
        n.node = self.game.deref().GetRoot()
        return n

    @property
    def is_const_sum(self) -> bool:
        """Returns whether the game is constant sum."""
        return self.game.deref().IsConstSum()

    @property
    def is_perfect_recall(self) -> bool:
        """Returns whether the game is perfect recall.

        By convention, games with a strategic representation have perfect recall as they
        are treated as simultaneous-move games.
        """
        return self.game.deref().IsPerfectRecall()

    @property
    def min_payoff(self) -> typing.Union[decimal.Decimal, Rational]:
        """Returns the minimum payoff in the game."""
        return rat_to_py(self.game.deref().GetMinPayoff(0))

    @property
    def max_payoff(self) -> typing.Union[decimal.Decimal, Rational]:
        """Returns the maximum payoff in the game."""
        return rat_to_py(self.game.deref().GetMaxPayoff(0))

    def set_chance_probs(self, infoset: Infoset, probs) -> Game:
        """Set the action probabilities at chance information set `infoset`.

        Parameters
        ----------
        infoset : Infoset
            The chance information set at which to set the action probabilities.
        probs : array-like
            The action probabilities to set

        Returns
        -------
        Game
            The operation modifies the game.  A reference to the game is also returned.

        Raises
        ------
        MismatchError
            If `infoset` is not an information set in this game
        UndefinedOperationError
            If `infoset` is not an information set of the chance player
        IndexError
            If the length of `probs` is not the same as the number of actions at the information set
        ValueError
            If any of the elements of `probs` are not interpretable as numbers, or the values of `probs` are not
            nonnegative numbers that sum to exactly one.
        """
        if infoset.game != self:
            raise MismatchError("set_chance_probs() first argument must be an infoset in the same game")
        if not infoset.is_chance:
            raise UndefinedOperationError("set_chance_probs() first argument must be a chance infoset")
        if len(infoset.actions) != len(probs):
            raise IndexError("set_chance_probs(): must specify exactly one probability per action")
        numbers = Array[c_Number](len(probs))
        for i in range(1, len(probs)+1):
            setitem_array_number(numbers, i, _to_number(probs[i-1]))
        try:
            self.game.deref().SetChanceProbs(infoset.infoset, numbers)
        except RuntimeError:
            raise ValueError("set_chance_probs(): must specify non-negative probabilities that sum to one")
        return self

    def _get_contingency(self, *args):
        psp = cython.declare(shared_ptr[c_PureStrategyProfile])
        psp = make_shared[c_PureStrategyProfile](self.game.deref().NewPureStrategyProfile())

        for (pl, st) in enumerate(args):
            deref(psp).deref().SetStrategy(self.game.deref().GetPlayer(pl+1).deref().GetStrategy(st+1))

        if self.is_tree:
            tree_outcome = TreeGameOutcome()
            tree_outcome.psp = psp
            tree_outcome.c_game = self.game
            return tree_outcome
        else:
            outcome = Outcome()
            outcome.outcome = deref(psp).deref().GetOutcome()
            return outcome

    # As of Cython 0.11.2, cython does not support the * notation for the argument
    # to __getitem__, which is required for multidimensional slicing to work. 
    # We work around this by providing a shim.
    def __getitem__(self, i):
        """Returns the `Outcome` associated with a profile of pure strategies.
        """
        try:
            if len(i) != len(self.players):
                raise KeyError("Number of strategies is not equal to the number of players")
        except TypeError:
            raise TypeError("contingency must be a tuple-like object")
        cont = [ 0 ] * len(self.players)
        for (pl, st) in enumerate(i):
            if isinstance(st, int):
                if st < 0 or st >= len(self.players[pl].strategies):
                    raise IndexError(f"Provided strategy index {st} out of range for player {pl}")
                cont[pl] = st
            elif isinstance(st, str):
                try:
                    cont[pl] = [ s.label for s in self.players[pl].strategies ].index(st)
                except ValueError:
                    raise IndexError(f"Provided strategy label '{st}' not defined")
            elif isinstance(st, Strategy):
                try:
                    cont[pl] = list(self.players[pl].strategies).index(st)
                except ValueError:
                    raise IndexError(f"Provided strategy '{st}' not available to player")
            else:
                raise TypeError("Must use a tuple of ints, strategy labels, or strategies")
        return self._get_contingency(*tuple(cont))

    def mixed_strategy_profile(self, data=None, rational=False) -> MixedStrategyProfile:
        """Returns a mixed strategy profile `MixedStrategyProfile`
        over the game.  If ``data`` is not specified, the mixed
        strategy profile is initialized to uniform randomization for each
        player over his strategies.  If the game has a tree
        representation, the mixed strategy profile is defined over the
        reduced strategic form representation.

        Parameters
        ----------
        data
            A nested list (or compatible type) with the
            same dimension as the strategy set of the game,
            specifying the probabilities of the strategies.

        rational
            If `True`, probabilities are represented using rational numbers;
            otherwise double-precision floating point numbers are used.
        """
        if not self.is_perfect_recall:
            raise UndefinedOperationError(
                "Mixed strategies not supported for games with imperfect recall."
            )
        if not rational:
            mspd = MixedStrategyProfileDouble()
            mspd.profile = make_shared[c_MixedStrategyProfileDouble](
                self.game.deref().NewMixedStrategyProfile(0.0)
            )
            if data is None:
                return mspd
            if len(data) != len(self.players):
                raise ValueError(
                    "Number of elements does not match number of players"
                )
            for (p, d) in zip(self.players, data):
                if len(p.strategies) != len(d):
                    raise ValueError(
                        f"Number of elements does not match number of "
                        f"strategies for {p}"
                    )
                for (s, v) in zip(p.strategies, d):
                    mspd[s] = float(v)
            return mspd
        else:
            mspr = MixedStrategyProfileRational()
            mspr.profile = make_shared[c_MixedStrategyProfileRational](
                self.game.deref().NewMixedStrategyProfile(c_Rational())
            )
            if data is None:
                return mspr
            if len(data) != len(self.players):
                raise ValueError(
                    "Number of elements does not match number of players"
                )
            for (p, d) in zip(self.players, data):
                if len(p.strategies) != len(d):
                    raise ValueError(
                        f"Number of elements does not match number of "
                        f"strategies for {p}"
                    )
                for (s, v) in zip(p.strategies, d):
                    mspr[s] = Rational(v)
            return mspr

    def mixed_behavior_profile(self, rational=False) -> MixedBehaviorProfile:
        """Returns a behavior strategy profile `MixedBehaviorProfile` over the game,
        initialized to uniform randomization for each player over his actions at each
        information set.

        Parameters
        ----------
        rational
            If `True`, probabilities are represented using rational numbers; otherwise
            double-precision floating point numbers are used.

        Raises
        ------
        UndefinedOperationError
            If the game does not have a tree representation.
        """
        if self.is_tree:
            if not rational:
                mbpd = MixedBehaviorProfileDouble()
                mbpd.profile = make_shared[c_MixedBehaviorProfileDouble](self.game)
                return mbpd
            else:
                mbpr = MixedBehaviorProfileRational()
                mbpr.profile = make_shared[c_MixedBehaviorProfileRational](self.game)
                return mbpr
        else:
            raise UndefinedOperationError(
                "Game must have a tree representation to create a mixed behavior profile"
            )
 
    def support_profile(self):
        return StrategySupportProfile(list(self.strategies), self)

    def num_nodes(self):
        if self.is_tree:
            return self.game.deref().NumNodes()
        return 0

    def unrestrict(self):
        return self

    def write(self, format='native') -> str:
        """Returns a serialization of the game.  Several output formats are
        supported, depending on the representation of the game.

        * `efg`: A representation of the game in
          :ref:`the .efg extensive game file format <file-formats-efg>`.
          Not available for games in strategic representation.
        * `nfg`: A representation of the game in
          :ref:`the .nfg strategic game file format <file-formats-nfg>`.
          For an extensive game, this uses the reduced strategic form
          representation.
        * `gte`: The XML representation used by the Game Theory Explorer
          tool.   Only available for extensive games.
        * `native`: The format most appropriate to the
          underlying representation of the game, i.e., `efg` or `nfg`.

        This method also supports exporting to other output formats
        (which cannot be used directly to re-load the game later, but
        are suitable for human consumption, inclusion in papers, and so
        on):

        * `html`: A rendering of the strategic form of the game as a
	      collection of HTML tables.  The first player is the row
	      chooser; the second player the column chooser.  For games with
	      more than two players, a collection of tables is generated,
	      one for each possible strategy combination of players 3 and higher.
        * `sgame`: A rendering of the strategic form of the game in
	      LaTeX, suitable for use with `Martin Osborne's sgame style
	      <https://www.economics.utoronto.ca/osborne/latex/>`_.
	      The first player is the row
	      chooser; the second player the column chooser.  For games with
	      more than two players, a collection of tables is generated,
	      one for each possible strategy combination of players 3 and higher.
        """
        if format == 'gte':
            return pygambit.gte.write_game(self)
        else:
            return WriteGame(self.game, format.encode('ascii')).decode('ascii')
